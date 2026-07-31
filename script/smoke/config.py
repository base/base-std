"""Run configuration for the b20 precompile smoketest.

Addresses, enum/constant values, derived role + policy-scope hashes, and the
per-run salt namespace. Environment (RPC_URL / DEPLOYER_PK / USER2_PK, plus
optional GAS_FLOAT_ETHER / SMOKE_SALT) is read here; the Makefile sources .env.
"""

from __future__ import annotations

import os
import secrets
from dataclasses import dataclass

from eth_typing import ChecksumAddress
from web3 import Web3

# Precompile addresses (from StdPrecompiles.sol — public, stable singletons).
B20_FACTORY: ChecksumAddress = Web3.to_checksum_address("0xB20f000000000000000000000000000000000000")
POLICY_REGISTRY: ChecksumAddress = Web3.to_checksum_address("0x8453000000000000000000000000000000000002")
ACTIVATION_REGISTRY: ChecksumAddress = Web3.to_checksum_address("0x8453000000000000000000000000000000000001")

# Feature ids gating the b20 precompiles, queried via ActivationRegistry.isActivated (the authoritative
# activation gate). Names mirror test/lib/mocks/ActivationRegistryFeatureList.sol.
FEATURE_B20_ASSET = Web3.keccak(text="base.b20_asset")
FEATURE_B20_STABLECOIN = Web3.keccak(text="base.b20_stablecoin")
FEATURE_POLICY_REGISTRY = Web3.keccak(text="base.policy_registry")

ZERO: ChecksumAddress = Web3.to_checksum_address("0x" + "00" * 20)


def amt(whole: int, decimals: int) -> int:
    """whole * 10**decimals (token base units)."""
    return whole * 10**decimals

# B20Variant enum (IB20Factory).
VARIANT_ASSET = 0
VARIANT_STABLECOIN = 1

# PolicyType enum (IPolicyRegistry). BLOCKLIST/ALLOWLIST are "simple" policies (decide from an
# address set); UNION/INTERSECT are "composite" gates over 2..4 simple children.
POLICY_TYPE_BLOCKLIST = 0
POLICY_TYPE_ALLOWLIST = 1
POLICY_TYPE_UNION = 2
POLICY_TYPE_INTERSECT = 3

# Composite child-set bounds. Outside this range the registry reverts
# ChildPoliciesOutsideOfRange(MIN_CHILD_POLICIES, MAX_CHILD_POLICIES). Distinct from the
# 64-account membership batch limit (BatchSizeTooLarge).
MIN_CHILD_POLICIES = 2
MAX_CHILD_POLICIES = 4

# Built-in policy IDs: ALWAYS_ALLOW = 0, ALWAYS_BLOCK = (uint64(ALLOWLIST) << 56) | 1.
ALWAYS_ALLOW_ID = 0
ALWAYS_BLOCK_ID = (1 << 56) | 1

# PausableFeature enum (IB20). SEIZE (Cobalt) governs `seizeWithMemo`.
FEATURE_TRANSFER = 0
FEATURE_MINT = 1
FEATURE_BURN = 2
FEATURE_SEIZE = 3

# Token decimals per variant.
ASSET_DECIMALS = 18
STABLECOIN_DECIMALS = 6

# ERC-165 + ERC-8056 interface ids advertised by the Asset variant (AssetV2 @ Cobalt). See
# src/interfaces/IScaledUIAmount.sol; `supportsInterface(SCALED_UI_AMOUNT_ID)` doubles as the
# probe that tells a Cobalt (ERC-8056 scheduled multiplier) chain apart from a pre-Cobalt one.
ERC165_ID = bytes.fromhex("01ffc9a7")
SCALED_UI_AMOUNT_ID = bytes.fromhex("a60bf13d")
NEW_UI_MULTIPLIER_ID = bytes.fromhex("4bd27648")
BALANCES_ID = bytes.fromhex("d890fd71")
# ERC-165 mandates 0xffffffff always reads false; any never-advertised id works as the negative probe.
UNADVERTISED_ID = bytes.fromhex("ffffffff")


def _role(name: str) -> bytes:
    """keccak256(name) for a role / policy-scope constant (B20Constants)."""
    return Web3.keccak(text=name)


DEFAULT_ADMIN_ROLE = b"\x00" * 32
MINT_ROLE = _role("MINT_ROLE")
BURN_ROLE = _role("BURN_ROLE")
BURN_BLOCKED_ROLE = _role("BURN_BLOCKED_ROLE")
SEIZE_ROLE = _role("SEIZE_ROLE")
PAUSE_ROLE = _role("PAUSE_ROLE")
UNPAUSE_ROLE = _role("UNPAUSE_ROLE")
METADATA_ROLE = _role("METADATA_ROLE")
OPERATOR_ROLE = _role("OPERATOR_ROLE")

TRANSFER_SENDER_POLICY = _role("TRANSFER_SENDER_POLICY")
TRANSFER_RECEIVER_POLICY = _role("TRANSFER_RECEIVER_POLICY")
TRANSFER_EXECUTOR_POLICY = _role("TRANSFER_EXECUTOR_POLICY")
MINT_RECEIVER_POLICY = _role("MINT_RECEIVER_POLICY")
SEIZE_HOLDER_POLICY = _role("SEIZE_HOLDER_POLICY")


@dataclass(frozen=True)
class Config:
    """Resolved run configuration from the environment."""

    rpc_url: str
    deployer_pk: str
    user2_pk: str
    gas_float_wei: int
    run_nonce: str
    salt_pinned: bool
    trace: bool
    faucet_url: str
    faucet_network: str
    faucet_amount: str
    faucet_min_wei: int
    observe_flip: bool
    flip_window_s: int
    flip_timeout_s: int

    @classmethod
    def from_env(cls) -> "Config":
        def need(key: str) -> str:
            val = os.environ.get(key)
            if not val:
                raise SystemExit(f"[smoke] ERROR: set {key} (see script/smoke/smoke/config.py)")
            return val

        pinned = os.environ.get("SMOKE_SALT")
        gas_ether = os.environ.get("GAS_FLOAT_ETHER", "0.01")
        # The scheduled-multiplier journey asserts the pending state read-only by default (no time
        # travel on a live chain). SMOKE_OBSERVE_FLIP=1 additionally schedules a near-future update
        # and polls until it matures, to observe the lazy flip. Off by default: real-time coupling
        # would make the advisory run flap on a chain with slow/variable block times.
        observe_flip = os.environ.get("SMOKE_OBSERVE_FLIP", "0").strip().lower() in ("1", "true", "on", "yes")
        # Failure diagnostics emit a debug_traceCall/Transaction call tree. On by default (only fires on
        # failures); set SMOKE_TRACE=0 to print just the request + replayed revert data instead.
        trace = os.environ.get("SMOKE_TRACE", "1").strip().lower() not in ("0", "false", "off", "no", "")
        # Optional faucet top-up for the deployer (internal dev chains get nuked, wiping its balance).
        # Host/network stay in .env (gitignored) so no internal reference lands in committed code. Funding
        # only fires when the balance is below FAUCET_MIN_ETHER and both URL + network are set.
        return cls(
            rpc_url=need("RPC_URL"),
            deployer_pk=need("DEPLOYER_PK"),
            user2_pk=need("USER2_PK"),
            gas_float_wei=Web3.to_wei(gas_ether, "ether"),
            run_nonce=pinned or secrets.token_hex(16),
            salt_pinned=pinned is not None,
            trace=trace,
            faucet_url=os.environ.get("FAUCET_URL", "").strip(),
            faucet_network=os.environ.get("FAUCET_NETWORK", "").strip(),
            faucet_amount=os.environ.get("FAUCET_AMOUNT", "0.05").strip(),
            faucet_min_wei=Web3.to_wei(os.environ.get("FAUCET_MIN_ETHER", "0.02"), "ether"),
            observe_flip=observe_flip,
            flip_window_s=int(os.environ.get("SMOKE_FLIP_WINDOW_S", "30")),
            flip_timeout_s=int(os.environ.get("SMOKE_FLIP_TIMEOUT_S", "150")),
        )

    def salt_for(self, journey: str) -> bytes:
        """createB20 salt for a journey, namespaced by run_nonce (unique per run)."""
        return Web3.keccak(text=f"base-std.smoke.{journey}.{self.run_nonce}")

    def new_addr(self, label: str) -> ChecksumAddress:
        """Keyless address (recipient / list member); fresh per run."""
        h = Web3.keccak(text=f"base-std.smoke.addr.{label}.{self.run_nonce}")
        return Web3.to_checksum_address(h[-20:])
