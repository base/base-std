"""Chain harness: provider, signers, send/read, revert + event assertions.

Wraps web3 + the interface ABIs (read from forge `out/`) so journeys read like the contract
API. Every mutating call goes through `send`, which signs, broadcasts to the
live node, waits for the receipt, asserts success, and records it for the
flow-level `assert_events_emitted` check. Reads and expected-revert simulations
use `eth_call` against the node, so the real precompiles execute (no local EVM).

The transport is `ConsistentHTTPProvider` (see `provider.py`), which gives the whole run a single
read-your-writes view over a load-balanced pool of nodes. Without it, a read routed to a backend
that lags the one that accepted the preceding write observes pre-write state.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable

from eth_account import Account
from eth_account.signers.local import LocalAccount
from eth_typing import ChecksumAddress
from hexbytes import HexBytes
from web3 import Web3
from web3.contract.contract import Contract
from web3.exceptions import ContractLogicError
from web3.logs import DISCARD
from web3.types import TxReceipt

from . import config
from .abis import ASSET_ABI, FACTORY_ABI, POLICY_ABI, STABLECOIN_ABI
from .codec import topic0
from .errors import ERROR_BY_SELECTOR
from .provider import ConsistentHTTPProvider

# Solidity built-in `Panic(uint256)` selector. Not a custom error in any ABI, so it is not in
# `ERROR_BY_SELECTOR`; matched directly by `expect_raw_panic`.
PANIC_SELECTOR = bytes.fromhex("4e487b71")


class Skip(Exception):
    """Raised by a journey to signal it does not apply to this chain (recorded as a skip, not a fail).

    Mirrors the runner's activation-gate skip: a journey whose surface only exists on a later fork
    (e.g. the ERC-8056 scheduled multiplier at Cobalt) raises this on a pre-fork chain so the run
    reports chain/fork state rather than a contract defect.
    """


def log(msg: str) -> None:
    print(f"[smoke] {msg}", file=sys.stderr)


def run_collected(
    checks: "list[tuple[str, Callable[[], None]]]",
    *,
    label: str,
    informational: "frozenset[str] | set[str]" = frozenset(),
    step_prefix: str = "",
) -> None:
    """Run every check, recording failures instead of aborting at the first.

    `die()` raises SystemExit, so a plain sequence stops at the first failure and the remaining
    checks never execute. Each `(name, thunk)` is isolated and its failure recorded. Names in
    `informational` are reported but do not fail the run. Raises SystemExit at the end if any
    required check failed.
    """
    findings: list[tuple[str, str, bool]] = []
    for i, (name, thunk) in enumerate(checks, 1):
        step(f"{step_prefix}{i}", name)
        required = name not in informational
        try:
            thunk()
        except SystemExit as exc:
            detail = str(exc.code or "").replace("[smoke] ERROR: ", "")
            print(f"  ✗ {'FINDING' if required else 'info'}: {detail}", file=sys.stderr)
            findings.append((name, detail, required))
        except Exception as exc:  # noqa: BLE001 - harness/RPC error, surface as a finding
            detail = f"{type(exc).__name__}: {exc}"
            print(f"  ✗ ERROR: {detail}", file=sys.stderr)
            findings.append((name, detail, required))

    required_fail = [f for f in findings if f[2]]
    info_only = [f for f in findings if not f[2]]
    log(f"{label}: {len(checks) - len(findings)}/{len(checks)} checks held")
    for name, detail, _ in findings:
        log(f"  ✗ {name} — {detail}")
    if info_only:
        log(f"({len(info_only)} accepted divergence(s) reported as informational)")
    if required_fail:
        raise SystemExit(f"[smoke] {label}: {len(required_fail)} finding(s) need triage")


def step(n: object, desc: str) -> None:
    print(f"  \u2192 [{n}] {desc}", file=sys.stderr)


def ok(desc: str) -> None:
    print(f"  \u2713 {desc}", file=sys.stderr)


def die(msg: str) -> None:
    raise SystemExit(f"[smoke] ERROR: {msg}")


def skip(msg: str) -> None:
    """Abort the current journey as not-applicable to this chain (recorded as skip)."""
    raise Skip(msg)


class Chain:
    """Live-node harness bound to one run's config."""

    def __init__(self, cfg: config.Config) -> None:
        self.cfg = cfg
        self.w3 = Web3(ConsistentHTTPProvider(cfg.rpc_url))
        if not self.w3.is_connected():
            die(f"RPC_URL did not answer: {cfg.rpc_url}")
        self.chain_id = self.w3.eth.chain_id

        self.deployer: LocalAccount = Account.from_key(cfg.deployer_pk)
        self.user2: LocalAccount = Account.from_key(cfg.user2_pk)
        self.DEPLOYER: ChecksumAddress = self.deployer.address
        self.USER2: ChecksumAddress = self.user2.address
        self.ALICE = cfg.new_addr("alice")
        self.BOB = cfg.new_addr("bob")

        self.factory = self.w3.eth.contract(address=config.B20_FACTORY, abi=FACTORY_ABI)
        self.policy = self.w3.eth.contract(address=config.POLICY_REGISTRY, abi=POLICY_ABI)
        # Address-less handles for encoding bootstrap calldata (init-calls).
        self.asset_abi = self.w3.eth.contract(abi=ASSET_ABI)
        self.stablecoin_abi = self.w3.eth.contract(abi=STABLECOIN_ABI)

        self._receipts: list[TxReceipt] = []
        self._user2_funded = False
        self.trace = cfg.trace
        self._nonces: dict[ChecksumAddress, int] = {}

    # ── nonce ─────────────────────────────────────────────────────────────────
    def next_nonce(self, address: ChecksumAddress) -> int:
        """Next nonce to sign with, robust against a load-balanced pool.

        Across backends a `latest`/`pending` count can come back stale-low (a backend lagging the one
        that mined our last tx) and a reused value collides. We take the max of the node's pending count
        and a local monotonic counter, then advance the counter — so every signed tx in the run gets a
        unique, forward-only nonce regardless of which backend answered. The nonce is intentionally read
        from the head (not the consistency high-water block): it must reflect the account's latest state,
        not a historical snapshot, or the broadcast is rejected as "nonce too low".
        """
        pending = self.w3.eth.get_transaction_count(address, "pending")
        nonce = max(pending, self._nonces.get(address, 0))
        self._nonces[address] = nonce + 1
        return nonce

    # ── contracts at an address ─────────────────────────────────────────────
    def asset_at(self, address: ChecksumAddress) -> Contract:
        return self.w3.eth.contract(address=address, abi=ASSET_ABI)

    def stablecoin_at(self, address: ChecksumAddress) -> Contract:
        return self.w3.eth.contract(address=address, abi=STABLECOIN_ABI)

    # ── send / read ─────────────────────────────────────────────────────────
    def send(self, fn, account: LocalAccount) -> TxReceipt:
        """Sign + broadcast a contract function, wait, assert success, record it."""
        tx = fn.build_transaction(
            {"from": account.address, "nonce": self.next_nonce(account.address)}
        )
        signed = account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        if receipt["status"] != 1:
            self.trace_tx(tx_hash, label=f"{fn.fn_name} reverted")
            die(f"tx reverted: {fn.fn_name}")
        self._receipts.append(receipt)
        return receipt

    def fund_user2(self) -> None:
        """Send user2 a one-time gas float from the deployer."""
        if self._user2_funded:
            return
        step("fund", f"deployer \u2192 user2 gas float ({self.cfg.gas_float_wei} wei)")
        tx = {
            "from": self.DEPLOYER,
            "to": self.USER2,
            "value": self.cfg.gas_float_wei,
            "gas": 21000,
            "gasPrice": self.w3.eth.gas_price,
            "nonce": self.next_nonce(self.DEPLOYER),
            "chainId": self.chain_id,
        }
        signed = self.deployer.sign_transaction(tx)
        receipt = self.w3.eth.wait_for_transaction_receipt(self.w3.eth.send_raw_transaction(signed.raw_transaction))
        if receipt["status"] != 1:
            die("failed to fund user2")
        self._user2_funded = True
        ok("user2 funded")

    # ── activation preflight ──────────────────────────────────────────────────
    def features_activated(self) -> tuple[bool, str]:
        """Check the b20 features are switched on via the ActivationRegistry (the authoritative gate).

        The b20/policy precompiles are installed at fork >= Beryl and each feature is individually gated by
        the ActivationRegistry. `isActivated(bytes32)` is a never-revert view returning a bool. If the
        registry itself isn't installed (fork < Beryl) the call falls through to account state — an empty
        account returns `0x`, stub bytecode hits an invalid opcode — which we report as "registry not
        installed". A clean `false` means the feature exists but isn't activated. In any of these cases the
        invariant/lifecycle checks would be testing environment state, not contract logic, so the caller
        skips the journey instead of reporting findings. Returns (active, reason-if-not).
        """
        selector = bytes(Web3.keccak(text="isActivated(bytes32)")[:4])
        for label, feature in (
            ("base.b20_asset", config.FEATURE_B20_ASSET),
            ("base.b20_stablecoin", config.FEATURE_B20_STABLECOIN),
            ("base.policy_registry", config.FEATURE_POLICY_REGISTRY),
        ):
            try:
                ret = bytes(
                    self.w3.eth.call(
                        {"to": config.ACTIVATION_REGISTRY, "from": self.DEPLOYER, "data": HexBytes(selector + bytes(feature))}
                    )
                )
            except Exception as exc:  # noqa: BLE001 - reverting view => registry not intercepting
                return False, f"ActivationRegistry not installed (isActivated errored: {type(exc).__name__}) — fork < Beryl?"
            if len(ret) != 32:
                return False, f"ActivationRegistry not installed (isActivated returned {len(ret)} bytes) — fork < Beryl?"
            if int.from_bytes(ret, "big") == 0:
                return False, f"feature '{label}' is not activated on this chain"
        return True, ""

    # ── faucet preflight ──────────────────────────────────────────────────────
    def ensure_deployer_funded(self) -> None:
        """Top up the deployer via the configured faucet if its balance is below the floor.

        Internal dev chains (e.g. base-zeronet) are periodically nuked, which wipes the deployer's
        balance. This is opt-in and idempotent: it checks the balance first and only calls the faucet
        when underfunded, so it is a no-op on a persistently funded chain. URL + network come from
        `.env` (`FAUCET_URL`, `FAUCET_NETWORK`); amount and floor default but are overridable.
        """
        bal = self.w3.eth.get_balance(self.DEPLOYER)
        if bal >= self.cfg.faucet_min_wei:
            return
        if not (self.cfg.faucet_url and self.cfg.faucet_network):
            die(
                f"deployer {self.DEPLOYER} underfunded ({bal} wei < {self.cfg.faucet_min_wei}) and no "
                "faucet configured (set FAUCET_URL + FAUCET_NETWORK in .env)"
            )
        step("faucet", f"deployer balance {bal} wei < floor; requesting {self.cfg.faucet_amount} ETH")
        self._request_faucet(self.DEPLOYER, self.cfg.faucet_amount)
        deadline = time.time() + 60
        while time.time() < deadline:
            bal = self.w3.eth.get_balance(self.DEPLOYER)
            if bal >= self.cfg.faucet_min_wei:
                ok(f"deployer funded: {bal} wei")
                return
            time.sleep(2)
        die(f"deployer still underfunded after faucet request ({bal} wei < {self.cfg.faucet_min_wei})")

    def _request_faucet(self, address: ChecksumAddress, amount: str) -> None:
        """POST the faucet a top-up request for `address`. Blocks until the HTTP call returns."""
        payload = json.dumps(
            {"network": self.cfg.faucet_network, "token": "eth", "amount": amount, "address": address}
        ).encode()
        req = urllib.request.Request(
            self.cfg.faucet_url, data=payload, headers={"content-type": "application/json"}, method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                log(f"faucet HTTP {resp.status}: {resp.read(500).decode('utf-8', 'replace')}")
        except urllib.error.HTTPError as exc:
            die(f"faucet request failed: HTTP {exc.code} {exc.read(500).decode('utf-8', 'replace')}")
        except Exception as exc:  # noqa: BLE001 - network/timeout; surface clearly
            die(f"faucet request error: {type(exc).__name__}: {exc}")

    # ── assertions ───────────────────────────────────────────────────────────
    def assert_eq(
        self,
        got: object,
        want: object,
        desc: str,
        *,
        repro_fn=None,
        repro_overrides: dict | None = None,
        repro_call: dict | None = None,
        repro_tx: object | None = None,
    ) -> None:
        """Assert equality. On failure, dump the full RPC trace of the reproducing call/tx if provided.

        Pass a `repro_*` so the diagnostic can replay the offending call: `repro_fn` (+`repro_overrides`)
        for a bound contract function, `repro_call` for a hand-built tx dict, or `repro_tx` for a tx hash.
        """
        gn, wn = _norm(got), _norm(want)
        if gn != wn:
            self._diagnose(f"assert failed: {desc}", repro_fn, repro_overrides, repro_call, repro_tx)
            die(f"assert_eq failed [{desc}]: got={gn} want={wn}")
        ok(desc)

    def expect_revert(self, error_name: str, fn, frm: ChecksumAddress) -> None:
        """Simulate `fn` via eth_call from `frm`; assert it reverts with error_name.

        Resolves the name from the 4-byte selector in the revert data.
        """
        try:
            fn.call({"from": frm})
        except ContractLogicError as exc:
            data = getattr(exc, "data", None)
            got = None
            if isinstance(data, str) and data.startswith("0x") and len(data) >= 10:
                got = ERROR_BY_SELECTOR.get(data[:10].lower())
            if got == error_name:
                ok(f"reverts {error_name}")
                return
            self._diagnose(f"revert mismatch: want {error_name}", repro_fn=fn, repro_overrides={"from": frm})
            die(f"revert mismatch: got={got!r} want={error_name} (raw: {data or exc})")
        except Exception as exc:  # noqa: BLE001 - surface any non-revert failure
            die(f"expected revert {error_name} but call raised {type(exc).__name__}: {exc}")
        self._diagnose(f"expected revert {error_name} but call succeeded", repro_fn=fn, repro_overrides={"from": frm})
        die(f"expected revert {error_name} but call succeeded")

    @staticmethod
    def _revert_bytes(exc: ContractLogicError) -> bytes | None:
        data = getattr(exc, "data", None)
        if isinstance(data, str) and data.startswith("0x"):
            return bytes(HexBytes(data))
        if isinstance(data, (bytes, bytearray)):
            return bytes(data)
        return None

    def expect_abi_decode_failed(self, desc: str, fn, frm: ChecksumAddress) -> None:
        """Simulate `fn` via eth_call; assert Rust precompile AbiDecodeFailed revert shape.

        Dispatch decode failures encode as `function_selector || utf8_error`, not a typed
        custom error such as InvalidVariant().
        """
        fn_selector = bytes(HexBytes(fn.selector))
        try:
            fn.call({"from": frm})
        except ContractLogicError as exc:
            self._assert_abi_decode_revert(
                self._revert_bytes(exc), fn_selector, desc, repro_fn=fn, repro_overrides={"from": frm}
            )
            ok(desc)
            return
        except Exception as exc:  # noqa: BLE001 - surface any non-revert failure
            die(f"expected ABI decode failure for {desc} but call raised {type(exc).__name__}: {exc}")
        self._diagnose(f"expected ABI decode failure: {desc}", repro_fn=fn, repro_overrides={"from": frm})
        die(f"expected ABI decode failure for {desc} but call succeeded")

    def _assert_abi_decode_revert(
        self,
        raw: bytes | None,
        fn_selector: bytes,
        desc: str,
        *,
        repro_fn=None,
        repro_overrides: dict | None = None,
        repro_call: dict | None = None,
    ) -> None:
        if raw is None:
            self._diagnose(f"expected ABI decode failure: {desc}", repro_fn, repro_overrides, repro_call)
            die(f"expected ABI decode failure for {desc} but revert had no data")
        if len(raw) <= 4:
            self._diagnose(f"expected ABI decode failure: {desc}", repro_fn, repro_overrides, repro_call)
            die(f"expected ABI decode failure for {desc} but revert was only {len(raw)} byte(s): 0x{raw.hex()}")
        if raw[:4] != fn_selector:
            typed = ERROR_BY_SELECTOR.get(("0x" + raw[:4].hex()).lower())
            self._diagnose(f"expected ABI decode failure: {desc}", repro_fn, repro_overrides, repro_call)
            die(
                f"expected ABI decode failure for {desc} "
                f"(selector 0x{fn_selector.hex()}) but got 0x{raw[:4].hex()}"
                f"{f' ({typed})' if typed else ''} (raw: 0x{raw.hex()})"
            )

    def expect_raw_abi_decode_failed(
        self,
        desc: str,
        to: ChecksumAddress,
        data: bytes,
        *,
        value: int = 0,
        frm: ChecksumAddress | None = None,
    ) -> None:
        """Assert hand-built calldata reverts with AbiDecodeFailed (selector || utf8)."""
        if len(data) < 4:
            die(f"expected ABI decode failure for {desc} but calldata is shorter than 4 bytes")
        fn_selector = data[:4]
        tx = {"to": to, "from": frm or self.DEPLOYER, "data": HexBytes(data), "value": value}
        try:
            self.w3.eth.call(tx)
        except ContractLogicError as exc:
            self._assert_abi_decode_revert(self._revert_bytes(exc), fn_selector, desc, repro_call=tx)
            ok(desc)
            return
        except Exception as exc:  # noqa: BLE001 - surface any non-revert failure
            die(f"expected ABI decode failure for {desc} but call raised {type(exc).__name__}: {exc}")
        self._diagnose(f"expected ABI decode failure: {desc}", repro_call=tx)
        die(f"expected ABI decode failure for {desc} but call succeeded")

    def assert_log_order(self, receipt: TxReceipt, sig_a: str, sig_b: str, desc: str) -> None:
        """Assert event A is logged immediately before event B in the receipt."""
        a, b = topic0(sig_a), topic0(sig_b)
        tops = [HexBytes(lg["topics"][0]) for lg in receipt["logs"] if lg["topics"]]
        if not any(tops[i] == a and tops[i + 1] == b for i in range(len(tops) - 1)):
            die(f"log order [{desc}]: expected {sig_a} immediately before {sig_b}")
        ok(desc)

    @staticmethod
    def _emitted(receipt: TxReceipt, sig: str) -> bool:
        """Whether an event with signature `sig` appears in this receipt's logs."""
        want = topic0(sig)
        return any(lg["topics"] and HexBytes(lg["topics"][0]) == want for lg in receipt["logs"])

    def assert_log(self, receipt: TxReceipt, sig: str, desc: str) -> None:
        """Assert this receipt emitted an event with signature `sig`."""
        if not self._emitted(receipt, sig):
            die(f"expected event not emitted [{desc}]: {sig}")
        ok(desc)

    def assert_no_log(self, receipt: TxReceipt, sig: str, desc: str) -> None:
        """Assert this receipt did NOT emit an event with signature `sig` (e.g. the superseded V1 event)."""
        if self._emitted(receipt, sig):
            die(f"unexpected event emitted [{desc}]: {sig}")
        ok(desc)

    def event_args(self, receipt: TxReceipt, contract: Contract, event_name: str) -> dict:
        """Decode a single occurrence of `event_name` from THIS receipt and return its args.

        `assert_events_emitted` and `assert_log` are presence-only — an event with the right name but a
        WRONG payload passes them. Decode the specific receipt to assert on the emitted values.
        """
        decoded = getattr(contract.events, event_name)().process_receipt(receipt, errors=DISCARD)
        if not decoded:
            die(f"{event_name} not found in receipt")
        return dict(decoded[0]["args"])

    def supports_erc165(self, token: Contract, interface_id: bytes) -> bool:
        """ERC-165 `supportsInterface(interface_id)` on `token`, treating an absent/reverting selector as False.

        A pre-ERC-165 fork's Asset has no `supportsInterface` selector, so the call reverts; that (and a
        clean `false`) both mean "interface not advertised", which the caller uses to gate fork-specific flow.
        """
        try:
            return bool(token.functions.supportsInterface(interface_id).call())
        except Exception:  # noqa: BLE001 - a reverting/absent selector means "not supported"
            return False

    def assert_events_emitted(self, desc: str, *signatures: str) -> None:
        """Flow-level check: each signature's topic0 appears across recorded txs."""
        if not self._receipts:
            die(f"assert_events_emitted [{desc}]: no txs recorded this run")
        seen = {HexBytes(lg["topics"][0]) for r in self._receipts for lg in r["logs"] if lg["topics"]}
        missing = [s for s in signatures if topic0(s) not in seen]
        if missing:
            die(f"expected events not emitted [{desc}]: {', '.join(missing)}")
        ok(f"{desc} ({len(signatures)} event type{'s' if len(signatures) != 1 else ''} confirmed emitted)")

    # ── deploy / raw low-level calls ──────────────────────────────────────────
    def deploy(
        self, abi: list, bytecode: str, *args, account: LocalAccount | None = None, value: int = 0
    ) -> Contract:
        """Deploy a contract from abi+bytecode and return a bound handle (used for the probe).

        `value` attaches wei to the constructor (e.g. for a payable force-feeder that self-destructs
        its balance into a target). The returned handle points at the deployed address even if the
        constructor leaves no code there.
        """
        account = account or self.deployer
        factory = self.w3.eth.contract(abi=abi, bytecode=bytecode)
        overrides = {"from": account.address, "nonce": self.next_nonce(account.address)}
        if value:
            overrides["value"] = value
        tx = factory.constructor(*args).build_transaction(overrides)
        signed = account.sign_transaction(tx)
        receipt = self.w3.eth.wait_for_transaction_receipt(self.w3.eth.send_raw_transaction(signed.raw_transaction))
        if receipt["status"] != 1 or not receipt.get("contractAddress"):
            die("contract deploy reverted")
        return self.w3.eth.contract(address=receipt["contractAddress"], abi=abi)

    def raw_call(self, to: ChecksumAddress, data: bytes, *, value: int = 0, frm: ChecksumAddress | None = None) -> bytes:
        """eth_call with hand-built calldata; returns raw return bytes (traces + raises on revert)."""
        tx = {"to": to, "from": frm or self.DEPLOYER, "data": HexBytes(data), "value": value}
        try:
            return bytes(self.w3.eth.call(tx))
        except Exception:
            self.trace_call(tx, label="raw_call reverted")
            raise

    def expect_raw_revert(
        self,
        desc: str,
        to: ChecksumAddress,
        data: bytes,
        *,
        value: int = 0,
        frm: ChecksumAddress | None = None,
        error_name: str | None = None,
    ) -> None:
        """Simulate a hand-built call; assert it reverts. Optionally match the custom-error selector."""
        tx = {"to": to, "from": frm or self.DEPLOYER, "data": HexBytes(data), "value": value}
        try:
            self.w3.eth.call(tx)
        except ContractLogicError as exc:
            raw = getattr(exc, "data", None)
            got = None
            if isinstance(raw, str) and raw.startswith("0x") and len(raw) >= 10:
                got = ERROR_BY_SELECTOR.get(raw[:10].lower())
            if error_name is not None and got != error_name:
                self._diagnose(f"{desc}: revert mismatch", repro_call=tx)
                die(f"{desc}: revert mismatch got={got!r} want={error_name} (raw: {raw or exc})")
            ok(f"{desc} (reverts{f' {got}' if got else ''})")
            return
        except Exception as exc:  # noqa: BLE001 - any node-level rejection still counts as "not accepted"
            ok(f"{desc} (rejected: {type(exc).__name__})")
            return
        self._diagnose(f"{desc}: expected revert but call succeeded", repro_call=tx)
        die(f"{desc}: expected revert but call succeeded")

    def expect_raw_panic(
        self,
        desc: str,
        to: ChecksumAddress,
        data: bytes,
        code: int,
        *,
        frm: ChecksumAddress | None = None,
    ) -> None:
        """Simulate a hand-built call; assert it reverts with a Solidity `Panic(uint256)` of `code`.

        Asserts the raw revert data is `PANIC_SELECTOR` followed by the 32-byte `code` (e.g. 0x11 for
        arithmetic overflow).
        """
        tx = {"to": to, "from": frm or self.DEPLOYER, "data": HexBytes(data), "value": 0}
        try:
            self.w3.eth.call(tx)
        except ContractLogicError as exc:
            raw = self._revert_bytes(exc)
            if raw is None or len(raw) < 4 or raw[:4] != PANIC_SELECTOR:
                self._diagnose(f"{desc}: expected Panic({code:#x})", repro_call=tx)
                die(f"{desc}: expected Panic(uint256) 0x4e487b71 but got {('0x' + raw.hex()) if raw else raw!r}")
            got_code = int.from_bytes(raw[4:36], "big") if len(raw) >= 36 else None
            if got_code != code:
                self._diagnose(f"{desc}: wrong Panic code", repro_call=tx)
                die(f"{desc}: expected Panic code {code:#x} but got {got_code if got_code is None else hex(got_code)}")
            ok(f"{desc} (reverts Panic({code:#x}))")
            return
        except Exception as exc:  # noqa: BLE001 - surface any non-revert failure
            die(f"{desc}: expected Panic({code:#x}) but call raised {type(exc).__name__}: {exc}")
        self._diagnose(f"{desc}: expected Panic but call succeeded", repro_call=tx)
        die(f"{desc}: expected Panic({code:#x}) but call succeeded")

    def send_expecting_revert(self, fn, account: LocalAccount, *, gas: int = 2_000_000) -> TxReceipt:
        """Broadcast a real tx with explicit gas (skips estimation) and assert the receipt reverted."""
        tx = fn.build_transaction(
            {
                "from": account.address,
                "nonce": self.next_nonce(account.address),
                "gas": gas,
            }
        )
        signed = account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        if receipt["status"] != 0:
            self.trace_tx(tx_hash, label=f"{fn.fn_name} unexpectedly succeeded")
            die(f"expected on-chain revert but tx succeeded: {fn.fn_name}")
        return receipt

    # ── rpc tracing (failure diagnostics) ─────────────────────────────────────
    def _diagnose(
        self,
        label: str,
        repro_fn=None,
        repro_overrides: dict | None = None,
        repro_call: dict | None = None,
        repro_tx: object | None = None,
    ) -> None:
        """Best-effort: dump the full RPC trace of the offending call/tx. Never masks the real failure."""
        try:
            if repro_fn is not None:
                self.trace_call(self._fn_call_tx(repro_fn, repro_overrides), label=label)
            elif repro_call is not None:
                self.trace_call(repro_call, label=label)
            elif repro_tx is not None:
                self.trace_tx(repro_tx, label=label)
        except Exception as exc:  # noqa: BLE001 - diagnostics must not raise over the assertion
            log(f"(diagnostics failed: {type(exc).__name__}: {exc})")

    def _fn_call_tx(self, fn, overrides: dict | None = None) -> dict:
        """Reconstruct the eth_call tx dict for a bound contract function (for replay/trace)."""
        handle = self.w3.eth.contract(abi=fn.contract_abi)
        data = HexBytes(handle.encode_abi(fn.fn_name, args=list(fn.args)))
        tx = {"to": fn.address, "from": (overrides or {}).get("from", self.DEPLOYER), "data": data}
        if overrides and overrides.get("value"):
            tx["value"] = overrides["value"]
        return tx

    def _rpc_tx(self, tx: dict) -> dict:
        """Hex-encode a tx dict for the JSON-RPC debug_* params object."""
        out: dict = {}
        for key in ("from", "to"):
            if tx.get(key) is not None:
                out[key] = tx[key]
        data = tx.get("data")
        if data is not None:
            out["data"] = data if isinstance(data, str) else "0x" + bytes(data).hex()
        if tx.get("value"):
            out["value"] = hex(int(tx["value"]))
        if tx.get("gas"):
            out["gas"] = hex(int(tx["gas"]))
        return out

    def trace_call(self, tx: dict, *, block: str = "latest", label: str = "failed eth_call") -> None:
        """Print the exact eth_call request and a debug_traceCall (callTracer) call tree."""
        data = tx.get("data")
        dhex = data if isinstance(data, str) else "0x" + bytes(data or b"").hex()
        log(f"\u2500\u2500 rpc trace: {label} \u2500\u2500")
        log(f"  eth_call to={tx.get('to')} from={tx.get('from')} value={tx.get('value', 0)}")
        log(f"  selector={dhex[:10]} data={dhex}")
        if not self.trace:
            log("  (debug trace disabled; set SMOKE_TRACE=1 for the full call tree)")
            self._print_revert_data(tx, block)
            return
        resp = self.w3.provider.make_request(
            "debug_traceCall", [self._rpc_tx(tx), block, {"tracer": "callTracer", "tracerConfig": {"withLog": True}}]
        )
        self._print_trace_response(resp, fallback_tx=tx, block=block)

    def trace_tx(self, tx_hash: object, *, label: str = "failed tx") -> None:
        """Print receipt summary and a debug_traceTransaction (callTracer) call tree."""
        h = tx_hash.hex() if isinstance(tx_hash, (bytes, bytearray)) else str(tx_hash)
        if not h.startswith("0x"):
            h = "0x" + h
        log(f"\u2500\u2500 rpc trace: {label} \u2500\u2500")
        log(f"  tx={h}")
        try:
            rcpt = self.w3.eth.get_transaction_receipt(tx_hash)
            log(f"  status={rcpt['status']} gasUsed={rcpt['gasUsed']} block={rcpt['blockNumber']}")
        except Exception:  # noqa: BLE001 - receipt is best-effort context
            pass
        if not self.trace:
            log("  (debug trace disabled; set SMOKE_TRACE=1 for the full call tree)")
            return
        resp = self.w3.provider.make_request(
            "debug_traceTransaction", [h, {"tracer": "callTracer", "tracerConfig": {"withLog": True}}]
        )
        self._print_trace_response(resp)

    def _print_trace_response(self, resp: dict, *, fallback_tx: dict | None = None, block: str = "latest") -> None:
        err = resp.get("error")
        if err:
            log(f"  debug trace unavailable: {err.get('message', err) if isinstance(err, dict) else err}")
            if fallback_tx is not None:
                self._print_revert_data(fallback_tx, block)
            return
        log("  callTracer:")
        print(json.dumps(resp.get("result"), indent=2, default=str), file=sys.stderr)

    def _print_revert_data(self, tx: dict, block: str) -> None:
        """Fallback when debug_* is unsupported: replay the eth_call and decode any revert bytes."""
        try:
            self.w3.eth.call(
                {"to": tx.get("to"), "from": tx.get("from"), "data": HexBytes(tx.get("data") or b""),
                 "value": tx.get("value", 0)},
                block,
            )
            log("  replay: eth_call succeeded (no revert data)")
        except ContractLogicError as exc:
            raw = getattr(exc, "data", None)
            name = ERROR_BY_SELECTOR.get(raw[:10].lower()) if isinstance(raw, str) and len(raw) >= 10 else None
            log(f"  replay revert: data={raw} ({name or 'unknown/empty selector'})")
        except Exception as exc:  # noqa: BLE001 - surface whatever the node said
            log(f"  replay error: {type(exc).__name__}: {exc}")

    # ── factory / policy helpers ──────────────────────────────────────────────
    def predict_b20(self, variant: int, salt: bytes, sender: ChecksumAddress | None = None) -> ChecksumAddress:
        return self.factory.functions.getB20Address(variant, sender or self.DEPLOYER, salt).call()

    def create_b20(self, variant: int, salt: bytes, params: bytes, init_calls: list[bytes]) -> TxReceipt:
        return self.send(self.factory.functions.createB20(variant, salt, params, init_calls), self.deployer)

    def create_b20_fn(self, variant: int, salt: bytes, params: bytes, init_calls: list[bytes]):
        """A createB20 call object (not sent) for expect_revert on the edge cases."""
        return self.factory.functions.createB20(variant, salt, params, init_calls)

    def create_policy(self, admin: ChecksumAddress, ptype: int) -> int:
        receipt = self.send(self.policy.functions.createPolicy(admin, ptype), self.deployer)
        return self._policy_id_from(receipt)

    def create_policy_with_accounts(self, admin: ChecksumAddress, ptype: int, accounts: list[ChecksumAddress]) -> int:
        receipt = self.send(self.policy.functions.createPolicyWithAccounts(admin, ptype, accounts), self.deployer)
        return self._policy_id_from(receipt)

    def create_composite_policy(self, admin: ChecksumAddress, ptype: int, child_ids: list[int]) -> int:
        """Create a UNION/INTERSECT composite over existing simple policies; return the new id."""
        receipt = self.send(self.policy.functions.createCompositePolicy(admin, ptype, child_ids), self.deployer)
        return self._policy_id_from(receipt)

    def _policy_id_from(self, receipt: TxReceipt) -> int:
        events = self.policy.events.PolicyCreated().process_receipt(receipt, errors=DISCARD)
        if not events:
            die("PolicyCreated event not found in receipt")
        return int(events[0]["args"]["policyId"])

    def composite_children_from(self, receipt: TxReceipt, policy_id: int | None = None) -> list[int]:
        """Decode `CompositePolicyUpdated` from a SPECIFIC receipt and return its `childPolicyIds`."""
        events = self.policy.events.CompositePolicyUpdated().process_receipt(receipt, errors=DISCARD)
        if policy_id is not None:
            events = [e for e in events if int(e["args"]["policyId"]) == policy_id]
        if not events:
            suffix = f" for policyId={policy_id}" if policy_id is not None else ""
            die(f"CompositePolicyUpdated event not found in receipt{suffix}")
        return [int(child) for child in events[0]["args"]["childPolicyIds"]]


def _norm(v: object) -> object:
    """Normalize for comparison: lowercase hex/addresses so checksums match."""
    if isinstance(v, (bytes, bytearray)):
        return "0x" + bytes(v).hex()
    if isinstance(v, str) and v.startswith(("0x", "0X")):
        return v.lower()
    return v
