"""B20 seize smoketest — the Cobalt `seizeWithMemo` path.

Exercises the transfer-based seize surface added at Cobalt (V2): the dedicated
`SEIZE_ROLE`, the `SEIZE_HOLDER_POLICY` membership gate (an account is seizable when
it is NOT authorized by that policy), `seizeWithMemo` (`Transfer` -> `Memo` -> `Seized`,
supply-preserving because seize is a reassignment, not a burn), and the `SEIZE` pause
vector — plus the gates that must reject (`AccountNotSeizable`, role,
`InvalidReceiver`, `ContractPaused`) and the admin-op decoupling from the receiver
policy on `to`.

Fork-gated: the whole surface is Cobalt-only. The journey probes the
`SEIZE_HOLDER_POLICY()` getter and cleanly SKIPS on a pre-Cobalt chain (where the
seize selectors do not exist) — the same "chain/fork state, not a contract defect"
stance as the `multiplier` journey and the activation preflight.

Distinct from the `stablecoin` journey's freeze-and-seize, which covers the legacy
burn-based `burnBlocked` (unchanged at Cobalt: `TRANSFER_SENDER_POLICY` + `BURN` pause).
"""

from __future__ import annotations

from web3.exceptions import BadFunctionCallOutput, ContractLogicError

from .. import config
from ..chain import Chain, log, ok, skip, step
from ..codec import AssetCreateParams, init_call

MEMO = b"seize".ljust(32, b"\x00")


def _setup(c: Chain):
    salt = c.cfg.salt_for("seize")
    params = AssetCreateParams("Seizable Asset", "SEIZ", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    roles = [config.MINT_ROLE, config.SEIZE_ROLE, config.PAUSE_ROLE, config.UNPAUSE_ROLE]
    init_calls = [init_call(c.asset_abi, "grantRole", r, c.DEPLOYER) for r in roles]

    step("setup", "create ASSET token (admin=deployer, MINT+SEIZE+PAUSE+UNPAUSE -> deployer)")
    tok_addr = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(config.VARIANT_ASSET, salt, params, init_calls)
    tok = c.asset_at(tok_addr)
    c.assert_eq(c.factory.functions.isB20Initialized(tok_addr).call(), True, "token initialized")
    return tok


def _is_cobalt(c: Chain, tok) -> bool:
    """Cobalt probe: the `SEIZE_HOLDER_POLICY()` getter only resolves on the V2 wire surface.

    On a pre-Cobalt (Beryl / V1) chain the selector is unknown and the call reverts, so the seize
    surface is absent and the journey opts out.
    """
    try:
        scope = tok.functions.SEIZE_HOLDER_POLICY().call()
    except (ContractLogicError, BadFunctionCallOutput):
        return False
    return scope == config.SEIZE_HOLDER_POLICY


def _journey(c: Chain, tok) -> None:
    step(1, "getters: SEIZE_HOLDER_POLICY() and SEIZE_ROLE() match the keccak constants")
    c.assert_eq(tok.functions.SEIZE_HOLDER_POLICY().call(), config.SEIZE_HOLDER_POLICY, "SEIZE_HOLDER_POLICY scope")
    c.assert_eq(tok.functions.SEIZE_ROLE().call(), config.SEIZE_ROLE, "SEIZE_ROLE id")

    step(2, "mint(alice, 1000); mint(deployer, 10)")
    c.send(tok.functions.mint(c.ALICE, config.amt(1000, 18)), c.deployer)
    c.send(tok.functions.mint(c.DEPLOYER, config.amt(10, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(1000, 18), "alice balance")
    c.assert_eq(tok.functions.totalSupply().call(), config.amt(1010, 18), "total supply")

    step(3, "seizable setup: blocklist policy on SEIZE_HOLDER_POLICY, block alice (alice becomes seizable)")
    pid = c.create_policy(c.DEPLOYER, config.POLICY_TYPE_BLOCKLIST)
    c.send(tok.functions.updatePolicy(config.SEIZE_HOLDER_POLICY, pid), c.deployer)
    c.send(c.policy.functions.updateBlocklist(pid, True, [c.ALICE]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(pid, c.ALICE).call(), False, "alice not authorized (seizable)")
    c.assert_eq(c.policy.functions.isAuthorized(pid, c.BOB).call(), True, "bob authorized (not seizable)")

    step(4, "seizeWithMemo(alice, bob, 400, memo): Transfer -> Memo -> Seized; supply unchanged")
    receipt = c.send(tok.functions.seizeWithMemo(c.ALICE, c.BOB, config.amt(400, 18), MEMO), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(600, 18), "alice balance after seize")
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(400, 18), "bob (destination) balance after seize")
    c.assert_eq(tok.functions.totalSupply().call(), config.amt(1010, 18), "total supply unchanged (seize is a transfer)")
    c.assert_log_order(
        receipt,
        "Transfer(address,address,uint256)",
        "Memo(address,bytes32)",
        "Memo immediately follows Transfer",
    )
    c.assert_log_order(
        receipt,
        "Memo(address,bytes32)",
        "Seized(address,address,address,uint256)",
        "Seized follows Memo",
    )
    seized = c.event_args(receipt, tok, "Seized")
    c.assert_eq(seized["caller"], c.DEPLOYER, "Seized.caller == deployer")
    c.assert_eq(seized["from"], c.ALICE, "Seized.from == alice")
    c.assert_eq(seized["to"], c.BOB, "Seized.to == bob")
    c.assert_eq(seized["amount"], config.amt(400, 18), "Seized.amount == 400")


def _edges(c: Chain, tok) -> None:
    step(5, "seize an account that is NOT seizable (bob authorized) -> AccountNotSeizable")
    c.expect_revert("AccountNotSeizable", tok.functions.seizeWithMemo(c.BOB, c.DEPLOYER, 1, MEMO), c.DEPLOYER)

    step(6, "role gate: user2 (no SEIZE_ROLE) -> AccessControlUnauthorizedAccount")
    c.expect_revert(
        "AccessControlUnauthorizedAccount",
        tok.functions.seizeWithMemo(c.ALICE, c.BOB, 1, MEMO),
        c.USER2,
    )

    step(7, "zero destination -> InvalidReceiver (seize is a reassignment, not a burn)")
    c.expect_revert("InvalidReceiver", tok.functions.seizeWithMemo(c.ALICE, config.ZERO, 1, MEMO), c.DEPLOYER)


def _decoupling(c: Chain, tok) -> None:
    step(8, "seize ignores the receiver policy on `to`: block bob on TRANSFER_RECEIVER_POLICY, seize still lands")
    recv_pid = c.create_policy(c.DEPLOYER, config.POLICY_TYPE_BLOCKLIST)
    c.send(tok.functions.updatePolicy(config.TRANSFER_RECEIVER_POLICY, recv_pid), c.deployer)
    c.send(c.policy.functions.updateBlocklist(recv_pid, True, [c.BOB]), c.deployer)
    c.assert_eq(c.policy.functions.isAuthorized(recv_pid, c.BOB).call(), False, "bob blocked as a receiver")
    # A normal transfer to bob would revert PolicyForbids; seize is an admin op and does not consult it.
    c.expect_revert("PolicyForbids", tok.functions.transfer(c.BOB, 1), c.DEPLOYER)
    c.send(tok.functions.seizeWithMemo(c.ALICE, c.BOB, config.amt(100, 18), MEMO), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(500, 18), "bob received the seize despite receiver policy")
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(500, 18), "alice debited")


def _pause(c: Chain, tok) -> None:
    step(9, "pause SEIZE: seizeWithMemo reverts ContractPaused; transfers are independent; unpause restores")
    c.send(tok.functions.pause([config.FEATURE_SEIZE]), c.deployer)
    c.assert_eq(tok.functions.isPaused(config.FEATURE_SEIZE).call(), True, "SEIZE paused")
    c.assert_eq(tok.functions.isPaused(config.FEATURE_TRANSFER).call(), False, "TRANSFER not paused (independent vector)")
    c.expect_revert("ContractPaused", tok.functions.seizeWithMemo(c.ALICE, c.BOB, 1, MEMO), c.DEPLOYER)
    # Independence: a normal transfer still works while SEIZE is paused (send to alice; bob is receiver-blocked).
    c.send(tok.functions.transfer(c.ALICE, config.amt(10, 18)), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), config.amt(510, 18), "transfer works while SEIZE paused")

    c.send(tok.functions.unpause([config.FEATURE_SEIZE]), c.deployer)
    c.assert_eq(tok.functions.isPaused(config.FEATURE_SEIZE).call(), False, "SEIZE unpaused")
    c.send(tok.functions.seizeWithMemo(c.ALICE, c.BOB, config.amt(100, 18), MEMO), c.deployer)
    c.assert_eq(tok.functions.balanceOf(c.BOB).call(), config.amt(600, 18), "seize works again after unpause")
    c.assert_eq(tok.functions.totalSupply().call(), config.amt(1010, 18), "total supply still unchanged across all seizes")


def _events(c: Chain) -> None:
    step(10, "expected events emitted across the flow")
    c.assert_events_emitted(
        "seize events",
        "B20Created(address,uint8,string,string,uint8,bytes)",
        "RoleGranted(bytes32,address,address)",
        "Transfer(address,address,uint256)",
        "Memo(address,bytes32)",
        "Seized(address,address,address,uint256)",
        "PolicyCreated(uint64,address,uint8)",
        "BlocklistUpdated(uint64,address,bool,address[])",
        "PolicyUpdated(bytes32,uint64,uint64)",
        "Paused(address,uint8[])",
        "Unpaused(address,uint8[])",
    )


def run(c: Chain) -> None:
    log("seize: starting")
    tok = _setup(c)
    if not _is_cobalt(c, tok):
        skip("Asset does not expose SEIZE_HOLDER_POLICY() — chain is pre-Cobalt (no seize surface)")
    ok("chain is Cobalt-capable (seize surface present)")
    _journey(c, tok)
    _edges(c, tok)
    _decoupling(c, tok)
    _pause(c, tok)
    _events(c)
    log("seize: OK")
