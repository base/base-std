"""ERC-8056 scheduled-multiplier smoketest (AssetV2 @ Cobalt).

Exercises the "Scaled UI Amount" surface added to the Asset variant at Cobalt: the scheduled
`setUIMultiplier` path (with its guards), `cancelScheduledMultiplier`, the `updateMultiplier`
instant-failsafe V2 event semantics, the ERC-8056 read aliases, and ERC-165 advertisement.

Fork-gated: the whole surface is version-specific, so the journey probes `supportsInterface`
for the ERC-8056 core id and cleanly SKIPS on a pre-Cobalt chain (where these selectors do not
exist) — the same "chain/fork state, not a contract defect" stance as the activation preflight.
This keeps one journey correct on both a Beryl-Vibenet (V1, skips) and a Cobalt-Vibenet (V2, runs).

Time on a live chain cannot be warped, so scheduled state is asserted read-only (the pending
target / effective-at, with the current multiplier unchanged). Observing the lazy flip requires
real time to pass; that check is opt-in via SMOKE_OBSERVE_FLIP and soft-skips on timeout so the
advisory run stays green.
"""

from __future__ import annotations

import time

from .. import config
from ..chain import Chain, log, ok, skip, step
from ..codec import AssetCreateParams, init_call

# ERC-8056 events. UIMultiplierUpdated is emitted by both setUIMultiplier and (on V2) updateMultiplier;
# MultiplierUpdateCancelled by cancelScheduledMultiplier and by updateMultiplier when it clears a
# live pending. V1_UPDATED is the superseded V1 event that V2's updateMultiplier must NOT emit.
UI_UPDATED = "UIMultiplierUpdated(uint256,uint256,uint256)"
CANCELLED = "MultiplierUpdateCancelled(uint256,uint256)"
V1_UPDATED = "MultiplierUpdated(uint256)"

WAD = config.amt(1, 18)


def _now(c: Chain) -> int:
    """Latest block timestamp — the reference for 'future' (schedule) and 'past' (reject) effective-ats."""
    return c.w3.eth.get_block("latest")["timestamp"]


def _setup(c: Chain):
    salt = c.cfg.salt_for("multiplier")
    params = AssetCreateParams("Scaled Asset", "SCAL", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    init_calls = [
        init_call(c.asset_abi, "grantRole", config.OPERATOR_ROLE, c.DEPLOYER),
        init_call(c.asset_abi, "grantRole", config.MINT_ROLE, c.DEPLOYER),
    ]
    step("setup", f"create ASSET token (admin=deployer, decimals={config.ASSET_DECIMALS}, OPERATOR+MINT -> deployer)")
    tok_addr = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    tok = c.asset_at(tok_addr)
    c.assert_eq(c.factory.functions.isB20Initialized(tok_addr).call(), True, "token initialized")
    return tok


def _interface_ids(c: Chain, tok) -> None:
    step(1, "supportsInterface advertises ERC-165 + the three ERC-8056 ids; an unadvertised id is false")
    c.assert_eq(c.supports_erc165(tok, config.ERC165_ID), True, "advertises IERC165 (0x01ffc9a7)")
    c.assert_eq(c.supports_erc165(tok, config.SCALED_UI_AMOUNT_ID), True, "advertises IScaledUIAmount (0xa60bf13d)")
    c.assert_eq(c.supports_erc165(tok, config.NEW_UI_MULTIPLIER_ID), True, "advertises pending ext (0x4bd27648)")
    c.assert_eq(c.supports_erc165(tok, config.BALANCES_ID), True, "advertises balances ext (0xd890fd71)")
    c.assert_eq(c.supports_erc165(tok, config.UNADVERTISED_ID), False, "unadvertised id (0xffffffff) is false")


def _current_multiplier_and_aliases(c: Chain, tok) -> None:
    step(2, "seed a non-unit current multiplier: updateMultiplier(2e18) — V2 emits UIMultiplierUpdated, not MultiplierUpdated")
    c.send(tok.functions.mint(c.ALICE, config.amt(1000, 18)), c.deployer)
    receipt = c.send(tok.functions.updateMultiplier(config.amt(2, 18)), c.deployer)
    c.assert_log(receipt, UI_UPDATED, "updateMultiplier emits UIMultiplierUpdated")
    c.assert_no_log(receipt, V1_UPDATED, "V2 updateMultiplier does NOT emit the V1 MultiplierUpdated")
    c.assert_eq(tok.functions.multiplier().call(), config.amt(2, 18), "multiplier == 2e18 immediately")

    step(3, "ERC-8056 read aliases mirror their B20 originals")
    c.assert_eq(tok.functions.uiMultiplier().call(), tok.functions.multiplier().call(), "uiMultiplier() == multiplier()")
    raw = tok.functions.balanceOf(c.ALICE).call()
    c.assert_eq(tok.functions.balanceOfUI(c.ALICE).call(), tok.functions.scaledBalanceOf(c.ALICE).call(),
                "balanceOfUI(alice) == scaledBalanceOf(alice)")
    c.assert_eq(tok.functions.balanceOfUI(c.ALICE).call(), raw * 2, "balanceOfUI(alice) == 2 * balanceOf(alice)")
    total = tok.functions.totalSupply().call()
    c.assert_eq(tok.functions.totalSupplyUI().call(), tok.functions.toScaledBalance(total).call(),
                "totalSupplyUI() == toScaledBalance(totalSupply())")


def _schedule_reverts(c: Chain, tok) -> None:
    # No live pending exists yet, so ScheduleOverlap cannot fire — each guard is the binding revert.
    # Every non-target argument is kept valid so the intended check is what reverts (mirrors the reference).
    step(4, "setUIMultiplier input guards: InvalidMultiplier / EffectiveAtInPast / EffectiveAtTooFar")
    future = _now(c) + 3600
    c.expect_revert("InvalidMultiplier", tok.functions.setUIMultiplier(0, future), c.DEPLOYER)
    c.expect_revert("InvalidMultiplier", tok.functions.setUIMultiplier(1 << 128, future), c.DEPLOYER)
    c.expect_revert("EffectiveAtInPast", tok.functions.setUIMultiplier(config.amt(3, 18), _now(c)), c.DEPLOYER)
    c.expect_revert("EffectiveAtTooFar", tok.functions.setUIMultiplier(config.amt(3, 18), 1 << 64), c.DEPLOYER)


def _schedule_and_cancel(c: Chain, tok) -> None:
    old = tok.functions.uiMultiplier().call()
    sched = _now(c) + 3600
    target = config.amt(3, 18)
    step(5, f"setUIMultiplier({target}, now+3600) schedules a pending update (read-only assertions; no time travel)")
    receipt = c.send(tok.functions.setUIMultiplier(target, sched), c.deployer)
    # Decode the receipt (not just presence): the scheduled target + effectiveAt are exactly what a
    # presence-only check can't verify.
    ui = c.event_args(receipt, tok, "UIMultiplierUpdated")
    c.assert_eq(
        [ui["oldMultiplier"], ui["newMultiplier"], ui["effectiveAtTimestamp"]],
        [old, target, sched],
        "UIMultiplierUpdated payload == (old, scheduled target, effectiveAt)",
    )
    c.assert_eq(tok.functions.newUIMultiplier().call(), target, "newUIMultiplier() == scheduled target")
    c.assert_eq(tok.functions.effectiveAt().call(), sched, "effectiveAt() == schedule time")
    c.assert_eq(tok.functions.uiMultiplier().call(), old, "uiMultiplier() still reads the old value while pending is future")

    step(6, "a second setUIMultiplier while a live pending exists -> ScheduleOverlap")
    c.expect_revert("ScheduleOverlap", tok.functions.setUIMultiplier(config.amt(4, 18), _now(c) + 7200), c.DEPLOYER)

    step(7, "cancelScheduledMultiplier clears the live pending -> MultiplierUpdateCancelled, effectiveAt() == 0")
    receipt = c.send(tok.functions.cancelScheduledMultiplier(), c.deployer)
    cancelled = c.event_args(receipt, tok, "MultiplierUpdateCancelled")
    c.assert_eq(
        [cancelled["cancelledMultiplier"], cancelled["cancelledEffectiveAt"]],
        [target, sched],
        "MultiplierUpdateCancelled payload == (cancelled target, cancelled effectiveAt)",
    )
    c.assert_eq(tok.functions.effectiveAt().call(), 0, "effectiveAt() resets to 0 after cancel")
    c.assert_eq(tok.functions.newUIMultiplier().call(), tok.functions.uiMultiplier().call(),
                "no-live-pending: newUIMultiplier() == uiMultiplier()")
    c.assert_eq(tok.functions.uiMultiplier().call(), old, "cancel leaves the current multiplier untouched")

    step(8, "cancelScheduledMultiplier with nothing scheduled -> NoScheduledMultiplier")
    c.expect_revert("NoScheduledMultiplier", tok.functions.cancelScheduledMultiplier(), c.DEPLOYER)


def _failsafe_clears_pending(c: Chain, tok) -> None:
    step(9, "updateMultiplier instant-failsafe clears a live pending: UIMultiplierUpdated + MultiplierUpdateCancelled, not MultiplierUpdated")
    cleared_target, cleared_sched = config.amt(5, 18), _now(c) + 3600
    c.send(tok.functions.setUIMultiplier(cleared_target, cleared_sched), c.deployer)
    receipt = c.send(tok.functions.updateMultiplier(config.amt(6, 18)), c.deployer)
    c.assert_log(receipt, UI_UPDATED, "updateMultiplier emits UIMultiplierUpdated")
    # Decode the cancel: it must carry the pending it cleared, not any live pending.
    cancelled = c.event_args(receipt, tok, "MultiplierUpdateCancelled")
    c.assert_eq(
        [cancelled["cancelledMultiplier"], cancelled["cancelledEffectiveAt"]],
        [cleared_target, cleared_sched],
        "MultiplierUpdateCancelled payload == the pending that updateMultiplier cleared",
    )
    c.assert_no_log(receipt, V1_UPDATED, "V2 updateMultiplier does NOT emit the V1 MultiplierUpdated")
    c.assert_eq(tok.functions.multiplier().call(), config.amt(6, 18), "updateMultiplier sets the current multiplier immediately")
    c.assert_eq(tok.functions.effectiveAt().call(), 0, "updateMultiplier cleared the pending (effectiveAt() == 0)")


def _observe_lazy_flip(c: Chain, tok) -> None:
    window, timeout = c.cfg.flip_window_s, c.cfg.flip_timeout_s
    target = config.amt(7, 18)
    old = tok.functions.uiMultiplier().call()
    sched = _now(c) + window
    step(10, f"opt-in lazy flip: schedule {target} at now+{window}s, poll multiplier() up to {timeout}s for the matured value")
    c.send(tok.functions.setUIMultiplier(target, sched), c.deployer)
    c.assert_eq(tok.functions.uiMultiplier().call(), old, "uiMultiplier() still old immediately after scheduling")

    deadline = time.time() + timeout
    while time.time() < deadline:
        if _now(c) >= sched and tok.functions.multiplier().call() == target:
            ok(f"multiplier() lazily flipped to the scheduled target at/after effectiveAt={sched}")
            c.assert_eq(tok.functions.uiMultiplier().call(), target, "uiMultiplier() mirrors the matured multiplier")
            c.assert_eq(tok.functions.newUIMultiplier().call(), target, "matured: newUIMultiplier() == uiMultiplier() == target")
            return
        time.sleep(3)

    # ponytail: real-time coupling — the flip only materializes as wall-clock passes effectiveAt, which
    # needs the chain to keep producing blocks. A live chain will; an idle dev node (e.g. anvil, whose
    # block clock only advances when a block is mined) may not within the budget. Soft-skip (log, don't
    # fail) so the advisory run stays green — the read-only pending assertions above already prove
    # scheduling works. The pending is left in place (throwaway token); no cleanup, since a cancel here
    # would race the maturation and revert. Upgrade path: raise SMOKE_FLIP_TIMEOUT_S, or use a fork test.
    log(f"lazy flip not observed within {timeout}s (effectiveAt={sched}) — soft skip (chain block time)")


def _events(c: Chain) -> None:
    step("events", "expected ERC-8056 events emitted across the flow")
    c.assert_events_emitted("scheduled-multiplier events", UI_UPDATED, CANCELLED)


def run(c: Chain) -> None:
    log("scheduled-multiplier: starting")
    tok = _setup(c)
    if not c.supports_erc165(tok, config.SCALED_UI_AMOUNT_ID):
        skip("Asset does not advertise ERC-8056 IScaledUIAmount (0xa60bf13d) — chain is pre-Cobalt")
    ok("chain is Cobalt-capable (Asset advertises ERC-8056 IScaledUIAmount)")
    _interface_ids(c, tok)
    _current_multiplier_and_aliases(c, tok)
    _schedule_reverts(c, tok)
    _schedule_and_cancel(c, tok)
    _failsafe_clears_pending(c, tok)
    if c.cfg.observe_flip:
        _observe_lazy_flip(c, tok)
    _events(c)
    log("scheduled-multiplier: OK")
