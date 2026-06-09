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

# PolicyType enum (IPolicyRegistry).
POLICY_TYPE_BLOCKLIST = 0
POLICY_TYPE_ALLOWLIST = 1

# Built-in policy IDs: ALWAYS_ALLOW = 0, ALWAYS_BLOCK = (uint64(ALLOWLIST) << 56) | 1.
ALWAYS_ALLOW_ID = 0
ALWAYS_BLOCK_ID = (1 << 56) | 1

# PausableFeature enum (IB20).
FEATURE_TRANSFER = 0
FEATURE_MINT = 1
FEATURE_BURN = 2

# Token decimals per variant.
ASSET_DECIMALS = 18
STABLECOIN_DECIMALS = 6


def _role(name: str) -> bytes:
    """keccak256(name) for a role / policy-scope constant (B20Constants)."""
    return Web3.keccak(text=name)


DEFAULT_ADMIN_ROLE = b"\x00" * 32
MINT_ROLE = _role("MINT_ROLE")
BURN_ROLE = _role("BURN_ROLE")
BURN_BLOCKED_ROLE = _role("BURN_BLOCKED_ROLE")
PAUSE_ROLE = _role("PAUSE_ROLE")
UNPAUSE_ROLE = _role("UNPAUSE_ROLE")
METADATA_ROLE = _role("METADATA_ROLE")
OPERATOR_ROLE = _role("OPERATOR_ROLE")

TRANSFER_SENDER_POLICY = _role("TRANSFER_SENDER_POLICY")
TRANSFER_RECEIVER_POLICY = _role("TRANSFER_RECEIVER_POLICY")
TRANSFER_EXECUTOR_POLICY = _role("TRANSFER_EXECUTOR_POLICY")
MINT_RECEIVER_POLICY = _role("MINT_RECEIVER_POLICY")


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

    @classmethod
    def from_env(cls) -> "Config":
        def need(key: str) -> str:
            val = os.environ.get(key)
            if not val:
                raise SystemExit(f"[smoke] ERROR: set {key} (see script/smoke/smoke/config.py)")
            return val

        pinned = os.environ.get("SMOKE_SALT")
        gas_ether = os.environ.get("GAS_FLOAT_ETHER", "0.01")
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
        )

    def salt_for(self, journey: str) -> bytes:
        """createB20 salt for a journey, namespaced by run_nonce (unique per run)."""
        return Web3.keccak(text=f"base-std.smoke.{journey}.{self.run_nonce}")

    def new_addr(self, label: str) -> ChecksumAddress:
        """Keyless address (recipient / list member); fresh per run."""
        h = Web3.keccak(text=f"base-std.smoke.addr.{label}.{self.run_nonce}")
        return Web3.to_checksum_address(h[-20:])
