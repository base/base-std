"""Precompile EVM-context invariant smoketest.

Audits the behaviors Solidity grants for free that a precompile has no notion of and must implement
explicitly: payable rejection, selector dispatch, strict ABI decode (non-canonical calldata rejected),
STATICCALL read-only enforcement, returndata fidelity, gas containment, and revert atomicity. Two layers:

  * raw `eth_call` with hand-built (often deliberately malformed) calldata, straight from web3 — for
    inputs the Solidity compiler would never emit (dirty high bits, unknown selectors, truncated args,
    value attached to a non-payable method);
  * a deployed `PrecompileProbe` contract for the cases that need a real caller frame (STATICCALL,
    DELEGATECALL, value forwarding, gas forwarding, revert atomicity).

Unlike the lifecycle journeys, the assertions here encode the *desired* invariant — a failure is a
precompile finding to triage, not a flaky test. The runner therefore does NOT fail fast: it runs every
check, prints a summary, and exits non-zero only at the end if any required invariant did not hold. To
accept a known divergence, add its check name to `INFORMATIONAL` — it will still be reported but won't
fail the run.
"""

from __future__ import annotations

import sys
from collections.abc import Callable

from hexbytes import HexBytes
from web3 import Web3

from .. import config
from ..abis import forcefeeder_artifact, probe_artifact
from ..chain import Chain, log, ok, step
from ..codec import AssetCreateParams, init_call

FACTORY = config.B20_FACTORY
POLICY = config.POLICY_REGISTRY
ALLOWLIST = config.POLICY_TYPE_ALLOWLIST

# Check names that are known/accepted divergences: reported, but do not fail the run.
INFORMATIONAL: set[str] = set()


def _clean(contract, fn_name: str, *args) -> bytes:
    """Canonical ABI calldata (selector + args) for a function on a bound contract handle."""
    return bytes(HexBytes(contract.encode_abi(fn_name, args=list(args))))


def _selector(sig: str) -> bytes:
    return bytes(Web3.keccak(text=sig)[:4])


def _addr_word(address: str) -> bytes:
    return bytes(12) + bytes(HexBytes(address))


# ── raw calldata edges (no helper contract; web3 emits bytes Solidity wouldn't) ────────────────────
def _payable_rejected(c: Chain, _probe) -> None:
    create_data = _clean(c.policy, "createPolicy", c.DEPLOYER, ALLOWLIST)
    c.expect_raw_revert("value on createPolicy", POLICY, create_data, value=1)


def _unknown_selector_reverts(c: Chain, _probe) -> None:
    c.expect_raw_revert("unknown selector", FACTORY, b"\xde\xad\xbe\xef")


def _empty_calldata_reverts(c: Chain, _probe) -> None:
    c.expect_raw_revert("empty calldata", FACTORY, b"")


def _truncated_args_revert(c: Chain, _probe) -> None:
    truncated = _selector("createPolicy(address,uint8)") + _addr_word(c.DEPLOYER)
    c.expect_raw_revert("truncated calldata", POLICY, truncated)


def _enum_out_of_range_reverts(c: Chain, _probe) -> None:
    bad_enum = _selector("createPolicy(address,uint8)") + _addr_word(c.DEPLOYER) + (5).to_bytes(32, "big")
    c.expect_raw_revert("enum out of range", POLICY, bad_enum)


def _dirty_high_bits_rejected(c: Chain, _probe) -> None:
    pid, acct = config.ALWAYS_BLOCK_ID, c.BOB
    sel = _selector("isAuthorized(uint64,address)")
    dirty = sel + (b"\xff" * 24 + pid.to_bytes(8, "big")) + (b"\xff" * 12 + bytes(HexBytes(acct)))
    c.raw_call(POLICY, _clean(c.policy, "isAuthorized", pid, acct))
    ok("clean isAuthorized succeeds")
    c.expect_raw_abi_decode_failed("dirty high bits AbiDecodeFailed", POLICY, dirty)


# ── caller-frame context (requires the deployed PrecompileProbe) ───────────────────────────────────
def _staticcall_read_only(c: Chain, probe) -> None:
    create_data = _clean(c.policy, "createPolicy", c.DEPLOYER, ALLOWLIST)
    fn = probe.functions.probeStaticcall(POLICY, create_data)
    okflag, _ = fn.call()
    c.assert_eq(okflag, False, "mutating call fails under STATICCALL", repro_fn=fn)


def _value_forwarding_rejected(c: Chain, probe) -> None:
    create_data = _clean(c.policy, "createPolicy", c.DEPLOYER, ALLOWLIST)
    overrides = {"from": c.DEPLOYER, "value": 1}
    fn = probe.functions.probeCall(POLICY, create_data)
    res = fn.call(overrides)
    c.assert_eq(res[0], False, "createPolicy rejects forwarded value", repro_fn=fn, repro_overrides=overrides)


def _returndata_fidelity(c: Chain, probe) -> None:
    zero_create = _clean(c.policy, "createPolicy", config.ZERO, ALLOWLIST)
    fn = probe.functions.probeReturndata(POLICY, zero_create)
    okflag, raw = fn.call()
    c.assert_eq(okflag, False, "createPolicy(0) reverts", repro_fn=fn)
    c.assert_eq(
        "0x" + bytes(raw)[:4].hex(),
        "0x" + _selector("ZeroAddress()").hex(),
        "returndata carries ZeroAddress",
        repro_fn=fn,
    )


def _oog_contained(c: Chain, probe) -> None:
    zero_create = _clean(c.policy, "createPolicy", config.ZERO, ALLOWLIST)
    fn = probe.functions.probeCallWithGas(POLICY, zero_create, 100)
    res = fn.call()
    c.assert_eq(res[0], False, "sub-call with 100 gas fails", repro_fn=fn)
    ok("outer frame returned (OOG did not kill the whole call)")


def _atomicity(c: Chain, probe) -> None:
    # A reverted mint must leave totalSupply/balances untouched AND commit no Transfer log. Deploy a
    # token, grant the probe MINT_ROLE (bootstrap window bypasses the role gate), then have the probe
    # mint-then-revert in a single tx and assert nothing persisted.
    salt = c.cfg.salt_for("invariants-atomicity")
    params = AssetCreateParams("Atomic", "ATOM", c.DEPLOYER, config.ASSET_DECIMALS).encode()
    tok_addr = c.predict_b20(config.VARIANT_ASSET, salt)
    c.create_b20(
        config.VARIANT_ASSET, salt, params, [init_call(c.asset_abi, "grantRole", config.MINT_ROLE, probe.address)]
    )
    tok = c.asset_at(tok_addr)

    supply_before = tok.functions.totalSupply().call()
    alice_before = tok.functions.balanceOf(c.ALICE).call()
    mint_data = init_call(c.asset_abi, "mint", c.ALICE, config.amt(1000, 18))
    receipt = c.send_expecting_revert(probe.functions.callThenRevert(tok_addr, mint_data), c.deployer)

    transfer_topic = HexBytes(Web3.keccak(text="Transfer(address,address,uint256)"))
    committed = any(lg["topics"] and HexBytes(lg["topics"][0]) == transfer_topic for lg in receipt["logs"])
    c.assert_eq(committed, False, "reverted mint committed no Transfer log")
    c.assert_eq(tok.functions.totalSupply().call(), supply_before, "totalSupply unchanged after reverted mint")
    c.assert_eq(tok.functions.balanceOf(c.ALICE).call(), alice_before, "alice balance unchanged after reverted mint")


def _create_gas_independent_of_prefunded_balance(c: Chain, _probe) -> None:
    params = AssetCreateParams("GasProbe", "GASP", c.DEPLOYER, config.ASSET_DECIMALS).encode()

    salt_ctrl = c.cfg.salt_for("invariants-gas-control")
    gas_unfunded = c.create_b20(config.VARIANT_ASSET, salt_ctrl, params, [])["gasUsed"]

    salt_fed = c.cfg.salt_for("invariants-gas-prefunded")
    target = c.predict_b20(config.VARIANT_ASSET, salt_fed)
    abi, bytecode = forcefeeder_artifact()
    c.deploy(abi, bytecode, target, value=1)  # SELFDESTRUCT 1 wei into the predicted token address
    fed = c.w3.eth.get_balance(target)
    c.assert_eq(fed >= 1, True, f"force-fed ether landed at predicted token address ({fed} wei @ {target})")

    gas_prefunded = c.create_b20(config.VARIANT_ASSET, salt_fed, params, [])["gasUsed"]

    c.assert_eq(
        gas_prefunded < gas_unfunded,
        False,
        f"createB20 gas independent of target's prefunded balance "
        f"(unfunded={gas_unfunded}, prefunded={gas_prefunded}, discount={gas_unfunded - gas_prefunded})",
    )


# Ordered audit checklist: (name, fn). `name` doubles as the INFORMATIONAL downgrade key.
CHECKS: list[tuple[str, Callable[[Chain, object], None]]] = [
    ("payable rejected (value on non-payable createPolicy)", _payable_rejected),
    ("unknown selector reverts (no silent fallthrough)", _unknown_selector_reverts),
    ("empty calldata reverts (no implicit receive/fallback)", _empty_calldata_reverts),
    ("truncated args revert (strict ABI decode)", _truncated_args_revert),
    ("out-of-range enum reverts", _enum_out_of_range_reverts),
    ("dirty high bits rejected (strict ABI decode)", _dirty_high_bits_rejected),
    ("STATICCALL read-only enforced", _staticcall_read_only),
    ("value forwarding rejected through a contract", _value_forwarding_rejected),
    ("returndata fidelity (RETURNDATACOPY of revert payload)", _returndata_fidelity),
    ("OOG contained to sub-call", _oog_contained),
    ("revert atomicity (reverted mint: no Transfer log, supply/balance unchanged)", _atomicity),
    ("createB20 gas independent of force-fed target balance (SELFDESTRUCT)", _create_gas_independent_of_prefunded_balance),
]


def _detail(exc: SystemExit) -> str:
    return str(exc.code or "").replace("[smoke] ERROR: ", "")


def _setup(c: Chain):
    step("setup", "deploy PrecompileProbe helper")
    abi, bytecode = probe_artifact()
    probe = c.deploy(abi, bytecode)
    ok(f"probe deployed at {probe.address}")
    return probe


def run(c: Chain) -> None:
    log("precompile-invariants: starting (collect-all; findings reported at the end)")
    probe = _setup(c)

    findings: list[tuple[str, str, bool]] = []  # (name, detail, required)
    for i, (name, fn) in enumerate(CHECKS, 1):
        step(i, name)
        required = name not in INFORMATIONAL
        try:
            fn(c, probe)
        except SystemExit as exc:  # assertion/expectation failed inside a check
            detail = _detail(exc)
            tag = "FINDING" if required else "info"
            print(f"  \u2717 {tag}: {detail}", file=sys.stderr)
            findings.append((name, detail, required))
        except Exception as exc:  # noqa: BLE001 - harness/RPC error, surface as a finding
            detail = f"{type(exc).__name__}: {exc}"
            print(f"  \u2717 ERROR: {detail}", file=sys.stderr)
            findings.append((name, detail, required))

    required_fail = [f for f in findings if f[2]]
    info_only = [f for f in findings if not f[2]]
    log(f"precompile-invariants: {len(CHECKS) - len(findings)}/{len(CHECKS)} invariants held")
    for name, detail, _ in findings:
        log(f"  \u2717 {name} \u2014 {detail}")
    if info_only:
        log(f"({len(info_only)} accepted divergence(s) reported as informational)")
    if required_fail:
        raise SystemExit(f"[smoke] precompile-invariants: {len(required_fail)} finding(s) need triage")
    log("precompile-invariants: OK")
