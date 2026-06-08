# shellcheck shell=bash
# smoke-lib.sh — shared helpers for the b20 precompile bring-up smoketest.
#
# STUB: this is a scaffold for scope review. Function bodies are intentionally
# unimplemented (marked TODO). Sourced by each journey script; not run directly.
#
# The smoketest flexes the b20 precompiles (B20Factory, PolicyRegistry,
# ActivationRegistry, and the per-token precompiles) on a freshly-cut chain by
# sending real transactions with `cast` and asserting read-backs. It assumes the
# b20 features are already activated on the target chain and that $DEPLOYER_PK is
# funded in genesis. Everything is driven through env vars so no chain identity
# lands in this OSS repo.
#
# Required env:
#   RPC_URL      RPC endpoint of the target chain (e.g. a freshly-cut net).
#   DEPLOYER_PK  Funded private key. Privileged actor: token admin + every role,
#                primary holder, and policy admin #1.
#   USER2_PK     Second signer (need not be pre-funded; the deployer sends it a
#                gas float at runtime). The distinct `transferFrom` executor and
#                policy admin #2 (finalizes the two-step admin transfer).
# Optional env:
#   SMOKE_SALT   Suffix mixed into every createB20 salt so the suite can be
#                re-run on a chain that already holds the default-salt tokens.
#   GAS_FLOAT    Wei sent to USER2 before it signs (default: a small fixed float).

# ──────────────────────────────────────────────────────────────────────────────
# Precompile addresses (from StdPrecompiles.sol — public, stable singletons).
# ──────────────────────────────────────────────────────────────────────────────
readonly B20_FACTORY=0xB20f000000000000000000000000000000000000
readonly POLICY_REGISTRY=0x8453000000000000000000000000000000000002
readonly ACTIVATION_REGISTRY=0x8453000000000000000000000000000000000001

# B20Variant enum (IB20Factory).
readonly VARIANT_ASSET=0
readonly VARIANT_STABLECOIN=1

# PolicyType enum (IPolicyRegistry).
readonly POLICY_TYPE_BLOCKLIST=0
readonly POLICY_TYPE_ALLOWLIST=1

# Built-in policy IDs (PolicyRegistry README): ALWAYS_ALLOW = 0,
# ALWAYS_BLOCK = (ALLOWLIST << 56) | 1.
readonly ALWAYS_ALLOW_ID=0
# TODO: ALWAYS_BLOCK_ID — compute (uint64(1) << 56 | 1) as a decimal/hex literal.

# Asset decimals used by the asset journey (in [6,18]).
readonly ASSET_DECIMALS=18
readonly STABLECOIN_DECIMALS=6

# ──────────────────────────────────────────────────────────────────────────────
# Derived constants (filled at runtime via cast; declared here for reference).
# Role hashes are keccak256("MINT_ROLE") etc. (B20Constants); DEFAULT_ADMIN_ROLE
# is bytes32(0). Policy scopes are keccak256("TRANSFER_SENDER_POLICY") etc.
# ──────────────────────────────────────────────────────────────────────────────
# TODO: populate via role_hash / scope_hash helpers (cast keccak), e.g.
#   MINT_ROLE=$(role_hash MINT_ROLE)
#   TRANSFER_SENDER_POLICY=$(scope_hash TRANSFER_SENDER_POLICY)

# ──────────────────────────────────────────────────────────────────────────────
# Logging / control
# ──────────────────────────────────────────────────────────────────────────────

# log MSG — narrate a phase to stderr.
log() { echo "[smoke] $*" >&2; }

# die MSG — abort the whole run with a nonzero exit (CI signal).
die() { echo "[smoke] ERROR: $*" >&2; exit 1; }

# step N DESC — narrate a numbered step within a journey.
step() { :; } # TODO: echo "  → [$1] $2" >&2

# ok DESC — mark the most recent step as passed (✓).
ok() { :; } # TODO: echo "  ✓ $*" >&2

# ──────────────────────────────────────────────────────────────────────────────
# Preflight
# ──────────────────────────────────────────────────────────────────────────────

# preflight — validate required bins (cast) and env (RPC_URL/DEPLOYER_PK/USER2_PK)
#   are present, that RPC_URL answers eth_chainId, and that the b20 features are
#   activated (isActivated on ACTIVATION_REGISTRY). die() on any failure.
preflight() { :; } # TODO

# ──────────────────────────────────────────────────────────────────────────────
# Actors / addresses
# ──────────────────────────────────────────────────────────────────────────────

# deployer_addr — echo the address for DEPLOYER_PK (cast wallet address).
deployer_addr() { :; } # TODO

# user2_addr — echo the address for USER2_PK.
user2_addr() { :; } # TODO

# fund_user2 — send USER2 a gas float from the deployer (idempotent enough: only
#   tops up if USER2 balance < GAS_FLOAT). Call before any USER2-signed step.
fund_user2() { :; } # TODO

# new_addr LABEL — echo a fresh keyless address (deterministic from LABEL) used as
#   a token recipient / policy-list member / seize target. Never signs.
new_addr() { :; } # TODO: cast wallet address for keccak(LABEL+SMOKE_SALT), or a fixed table.

# ──────────────────────────────────────────────────────────────────────────────
# Salt / hashing helpers
# ──────────────────────────────────────────────────────────────────────────────

# salt_for JOURNEY — echo the deterministic createB20 salt for a journey,
#   keccak("base-std.smoke.<JOURNEY>" + SMOKE_SALT). Stable per fresh chain;
#   override SMOKE_SALT to re-run on a chain that already has the tokens.
salt_for() { :; } # TODO: cast keccak "base-std.smoke.$1${SMOKE_SALT:-}"

# role_hash NAME — echo keccak256(NAME) for a role constant (e.g. MINT_ROLE).
role_hash() { :; } # TODO: cast keccak "$1"  (DEFAULT_ADMIN_ROLE is bytes32(0))

# scope_hash NAME — echo keccak256(NAME) for a policy scope (e.g. TRANSFER_SENDER_POLICY).
scope_hash() { :; } # TODO: cast keccak "$1"

# ──────────────────────────────────────────────────────────────────────────────
# ABI encoding (cast-only) — the gnarly createB20 inputs and friends.
# ──────────────────────────────────────────────────────────────────────────────

# encode_asset_params NAME SYMBOL ADMIN DECIMALS — echo the ABI-encoded
#   B20AssetCreateParams blob (version byte = 1) for createB20's `params` arg.
encode_asset_params() { :; }
#   TODO: cast abi-encode 'x((uint8,string,string,address,uint8))' \
#           "(1,\"$1\",\"$2\",$3,$4)"

# encode_stablecoin_params NAME SYMBOL ADMIN CURRENCY — echo the ABI-encoded
#   B20StablecoinCreateParams blob (version byte = 1).
encode_stablecoin_params() { :; }
#   TODO: cast abi-encode 'x((uint8,string,string,address,string))' \
#           "(1,\"$1\",\"$2\",$3,\"$4\")"

# encode_init_calls CALLDATA... — echo the ABI-encoded bytes[] of bootstrap
#   initCalls from a list of pre-encoded calldata blobs.
encode_init_calls() { :; } # TODO: cast abi-encode 'x(bytes[])' "[$(join , "$@")]"

# call_grant_role ROLE ACCOUNT     — echo `cast calldata grantRole(bytes32,address)`.
# call_update_supply_cap CAP       — echo calldata updateSupplyCap(uint256).
# call_update_policy SCOPE POLICYID — echo calldata updatePolicy(bytes32,uint64).
# call_batch_mint RECIPS AMTS      — echo calldata batchMint(address[],uint256[]).
# call_update_multiplier M         — echo calldata updateMultiplier(uint256).
# (These wrap `cast calldata` for use inside encode_init_calls / announce().)
call_grant_role() { :; }        # TODO
call_update_supply_cap() { :; } # TODO
call_update_policy() { :; }     # TODO
call_batch_mint() { :; }        # TODO
call_update_multiplier() { :; } # TODO

# ──────────────────────────────────────────────────────────────────────────────
# Send / read / assert
# ──────────────────────────────────────────────────────────────────────────────

# send PK TO SIG ARGS... — cast send from PK; die() if status != 1. Echoes the
#   tx hash so callers can inspect logs.
send() { :; } # TODO: cast send --rpc-url "$RPC_URL" --private-key "$PK" "$TO" "$SIG" "$@"

# call TO SIG ARGS... — cast call (read); echo the decoded return value.
call() { :; } # TODO: cast call --rpc-url "$RPC_URL" "$TO" "$SIG" "$@"

# assert_eq GOT WANT DESC — die() unless GOT == WANT.
assert_eq() { :; } # TODO

# assert_call TO SIG ARGS... -- WANT DESC — call() then assert_eq the result.
assert_call() { :; } # TODO

# expect_revert SELECTOR -- PK TO SIG ARGS... — send the (expected-to-fail) call
#   and assert it reverts with the EXACT custom-error SELECTOR (e.g. the 4-byte
#   sig of PolicyForbids / SupplyCapExceeded). Parse cast's revert output; die()
#   if it succeeds or reverts with a different selector.
expect_revert() { :; } # TODO

# selector SIG — echo the 4-byte selector for an error/function signature, e.g.
#   selector 'PolicyForbids(bytes32,uint64)'  (cast sig).
selector() { :; } # TODO: cast sig "$1"

# assert_log_order TXHASH SIG_A SIG_B DESC — assert event SIG_A is logged
#   immediately before SIG_B in TXHASH's receipt (e.g. Transfer then Memo).
assert_log_order() { :; } # TODO: cast receipt --json | parse topics[0]
