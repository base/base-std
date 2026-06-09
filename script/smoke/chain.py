"""Chain harness: provider, signers, send/read, revert + event assertions.

Wraps web3 + the committed interface ABIs so journeys read like the contract
API. Every mutating call goes through `send`, which signs, broadcasts to the
live node, waits for the receipt, asserts success, and records it for the
flow-level `assert_events_emitted` check. Reads and expected-revert simulations
use `eth_call` against the node, so the real precompiles execute (no local EVM).
"""

from __future__ import annotations

import sys

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


def log(msg: str) -> None:
    print(f"[smoke] {msg}", file=sys.stderr)


def step(n: object, desc: str) -> None:
    print(f"  \u2192 [{n}] {desc}", file=sys.stderr)


def ok(desc: str) -> None:
    print(f"  \u2713 {desc}", file=sys.stderr)


def die(msg: str) -> None:
    raise SystemExit(f"[smoke] ERROR: {msg}")


class Chain:
    """Live-node harness bound to one run's config."""

    def __init__(self, cfg: config.Config) -> None:
        self.cfg = cfg
        self.w3 = Web3(Web3.HTTPProvider(cfg.rpc_url))
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

    # ── contracts at an address ─────────────────────────────────────────────
    def asset_at(self, address: ChecksumAddress) -> Contract:
        return self.w3.eth.contract(address=address, abi=ASSET_ABI)

    def stablecoin_at(self, address: ChecksumAddress) -> Contract:
        return self.w3.eth.contract(address=address, abi=STABLECOIN_ABI)

    # ── send / read ─────────────────────────────────────────────────────────
    def send(self, fn, account: LocalAccount) -> TxReceipt:
        """Sign + broadcast a contract function, wait, assert success, record it."""
        tx = fn.build_transaction(
            {"from": account.address, "nonce": self.w3.eth.get_transaction_count(account.address)}
        )
        signed = account.sign_transaction(tx)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        if receipt["status"] != 1:
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
            "nonce": self.w3.eth.get_transaction_count(self.DEPLOYER),
            "chainId": self.chain_id,
        }
        signed = self.deployer.sign_transaction(tx)
        receipt = self.w3.eth.wait_for_transaction_receipt(self.w3.eth.send_raw_transaction(signed.raw_transaction))
        if receipt["status"] != 1:
            die("failed to fund user2")
        self._user2_funded = True
        ok("user2 funded")

    # ── assertions ───────────────────────────────────────────────────────────
    def assert_eq(self, got: object, want: object, desc: str) -> None:
        gn, wn = _norm(got), _norm(want)
        if gn != wn:
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
            die(f"revert mismatch: got={got!r} want={error_name} (raw: {data or exc})")
        except Exception as exc:  # noqa: BLE001 - surface any non-revert failure
            die(f"expected revert {error_name} but call raised {type(exc).__name__}: {exc}")
        die(f"expected revert {error_name} but call succeeded")

    def assert_log_order(self, receipt: TxReceipt, sig_a: str, sig_b: str, desc: str) -> None:
        """Assert event A is logged immediately before event B in the receipt."""
        a, b = topic0(sig_a), topic0(sig_b)
        tops = [HexBytes(lg["topics"][0]) for lg in receipt["logs"] if lg["topics"]]
        if not any(tops[i] == a and tops[i + 1] == b for i in range(len(tops) - 1)):
            die(f"log order [{desc}]: expected {sig_a} immediately before {sig_b}")
        ok(desc)

    def assert_events_emitted(self, desc: str, *signatures: str) -> None:
        """Flow-level check: each signature's topic0 appears across recorded txs."""
        if not self._receipts:
            die(f"assert_events_emitted [{desc}]: no txs recorded this run")
        seen = {HexBytes(lg["topics"][0]) for r in self._receipts for lg in r["logs"] if lg["topics"]}
        missing = [s for s in signatures if topic0(s) not in seen]
        if missing:
            die(f"expected events not emitted [{desc}]: {', '.join(missing)}")
        ok(f"{desc} ({len(signatures)} event type{'s' if len(signatures) != 1 else ''} confirmed emitted)")

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

    def _policy_id_from(self, receipt: TxReceipt) -> int:
        events = self.policy.events.PolicyCreated().process_receipt(receipt, errors=DISCARD)
        if not events:
            die("PolicyCreated event not found in receipt")
        return int(events[0]["args"]["policyId"])


def _norm(v: object) -> object:
    """Normalize for comparison: lowercase hex/addresses so checksums match."""
    if isinstance(v, (bytes, bytearray)):
        return "0x" + bytes(v).hex()
    if isinstance(v, str) and v.startswith(("0x", "0X")):
        return v.lower()
    return v
