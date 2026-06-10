#!/usr/bin/env bash
# run-fork-tests.sh — run the base-std unit suite against a local anvil that
# dispatches Base's Rust precompiles, validating the Solidity reference against
# the live Rust impl from base/base.
#
# Both binaries (anvil + forge) come from the base-anvil fork of foundry-rs,
# which adds a single `--base` flag to NetworkConfigs that installs the B-20
# precompile suite into the EVM. Stock foundry binaries will NOT work.
#
# Workflow:
#   1. Launch anvil on $PORT with --base (registers Base precompiles).
#   2. Fund + impersonate the activation admin, activate the gated features.
#   3. Run forge --fork-url against anvil + the `fork` profile (which sets
#      base = true so forge's own EVM also dispatches to Base precompiles).
#   4. Tear down anvil regardless of success / failure.
#
# Any extra arguments to this script are forwarded to `forge test`. Use them
# to scope the run (e.g. --match-contract, --match-test, -vvvv).
#
# Env vars (with defaults):
#   ANVIL_BIN        path to the patched anvil binary
#                    (default: ../base-anvil/target/release/anvil, falling
#                    back to debug if release is missing)
#   FORGE_BIN        path to the patched forge binary
#                    (default: `forge` next to ANVIL_BIN)
#   PORT             local RPC port for anvil (default: 8546)
#   ACTIVATION_ADMIN address authorized to activate features
#                    (default: 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, the
#                    canonical local-dev admin)
#   ANVIL_LOG        anvil stdout/stderr log path (default: /tmp/anvil.log)
#   SKIP_ACTIVATE    comma-separated feature names or 0x ids to leave
#                    un-activated (default: none, so every feature is activated).
#                    Use to exercise the inactive-feature dispatch path, e.g.
#                    SKIP_ACTIVATE=POLICY_REGISTRY to run the policy-registry
#                    inactive-dispatch regression tests. Names and ids are
#                    matched case-insensitively.
#
# Exit codes:
#   0   forge test exit 0 (all targeted tests pass)
#   1   forge test exit non-zero (at least one targeted test fails — the
#       output is the cross-validation signal)
#   2   environment problem (missing binary, port in use, anvil failed to
#       start, activation tx failed)

set -euo pipefail

# ── Layout ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ANVIL_RELEASE="$REPO_ROOT/../base-anvil/target/release/anvil"
DEFAULT_ANVIL_DEBUG="$REPO_ROOT/../base-anvil/target/debug/anvil"

if [[ -z "${ANVIL_BIN:-}" ]]; then
    if [[ -x "$DEFAULT_ANVIL_RELEASE" ]]; then
        ANVIL_BIN="$DEFAULT_ANVIL_RELEASE"
    elif [[ -x "$DEFAULT_ANVIL_DEBUG" ]]; then
        ANVIL_BIN="$DEFAULT_ANVIL_DEBUG"
    else
        echo "ERROR: anvil binary not found. Expected at:" >&2
        echo "  $DEFAULT_ANVIL_RELEASE" >&2
        echo "  $DEFAULT_ANVIL_DEBUG" >&2
        echo "Build with: cd ../base-anvil && cargo build --release -p anvil -p forge" >&2
        echo "Or set ANVIL_BIN=/path/to/anvil." >&2
        exit 2
    fi
fi

if [[ -z "${FORGE_BIN:-}" ]]; then
    FORGE_BIN="$(dirname "$ANVIL_BIN")/forge"
    if [[ ! -x "$FORGE_BIN" ]]; then
        echo "ERROR: patched forge binary not found at $FORGE_BIN." >&2
        echo "Build with: cd $(dirname "$ANVIL_BIN")/../.. && cargo build --release -p forge" >&2
        echo "Or set FORGE_BIN=/path/to/forge." >&2
        echo "(System forge will NOT work — it lacks the --base injection." >&2
        echo " forge must come from the base-anvil fork of foundry-rs.)" >&2
        exit 2
    fi
fi

PORT="${PORT:-8546}"
ACTIVATION_ADMIN="${ACTIVATION_ADMIN:-0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc}"
REGISTRY=0x8453000000000000000000000000000000000001
LOG_FILE="${ANVIL_LOG:-/tmp/anvil.log}"

# Feature IDs mirror the canonical set in test/lib/mocks/ActivationRegistryFeatureList.sol
# (the Solidity reference is the source of truth). If a feature is added there, append its ID here.
FEATURE_IDS=(
    0xcdcc772fe4cbdb1029f822861176d09e646db96723d4c1e82ddfdeb8163ef54c  # B20_ASSET
    0xb582ebae03f16fee49a6763f78df482fb11ae73f103ed0d330bbe556aa90a43f  # POLICY_REGISTRY
    0xecfa0def2c10020caaf65e6155aa69c84b24892aaef76eeac52e0e2b3a0b8601  # B20_STABLECOIN
)

# Optional set of features to leave UN-activated (see header). Matched against
# both the canonical name and the raw id, case-insensitively. Default empty, so
# the standard cross-validation run activates everything as before.
SKIP_ACTIVATE="${SKIP_ACTIVATE:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[run-fork-tests] $*" >&2; }
die()  { echo "[run-fork-tests] ERROR: $*" >&2; exit 2; }

# Canonical name for a feature id (mirrors the comments on FEATURE_IDS and the
# Solidity ActivationRegistryFeatureList). Empty string for an unknown id.
feature_name() {
    case "$1" in
        0xcdcc772fe4cbdb1029f822861176d09e646db96723d4c1e82ddfdeb8163ef54c) echo B20_ASSET ;;
        0xb582ebae03f16fee49a6763f78df482fb11ae73f103ed0d330bbe556aa90a43f) echo POLICY_REGISTRY ;;
        0xecfa0def2c10020caaf65e6155aa69c84b24892aaef76eeac52e0e2b3a0b8601) echo B20_STABLECOIN ;;
        *) echo "" ;;
    esac
}

# Returns 0 (skip) if feature id $1 is named in SKIP_ACTIVATE, by either its
# canonical name or its raw id. Case-insensitive; whitespace-tolerant.
should_skip_activate() {
    [[ -z "$SKIP_ACTIVATE" ]] && return 1
    local fid="$1" name id_uc entry
    name="$(feature_name "$fid")"
    id_uc="$(printf '%s' "$fid" | tr '[:lower:]' '[:upper:]')"
    local IFS=','
    for entry in $SKIP_ACTIVATE; do
        entry="$(printf '%s' "$entry" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
        [[ -z "$entry" ]] && continue
        if [[ "$entry" == "$name" || "$entry" == "$id_uc" ]]; then
            return 0
        fi
    done
    return 1
}

rpc() {
    local method="$1"; shift
    local params="$1"; shift
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "http://localhost:$PORT"
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

command -v cast >/dev/null 2>&1 || die "cast not found (install foundry: https://getfoundry.sh)"
command -v curl >/dev/null 2>&1 || die "curl not found"

if lsof -i ":$PORT" >/dev/null 2>&1; then
    die "port $PORT is already in use. Set PORT=<other> or kill the existing listener."
fi

log "anvil:            $ANVIL_BIN"
log "forge:            $FORGE_BIN"
log "port:             $PORT"
log "activation admin: $ACTIVATION_ADMIN"
log "log file:         $LOG_FILE"
log "skip-activate:    ${SKIP_ACTIVATE:-<none>}"

# ── Launch anvil ──────────────────────────────────────────────────────────────

log "starting anvil…"
"$ANVIL_BIN" --base --base-activation-admin "$ACTIVATION_ADMIN" --port "$PORT" \
    > "$LOG_FILE" 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null; wait $ANVIL_PID 2>/dev/null; true' EXIT

# Poll for the RPC port to come up (up to 10s).
for i in $(seq 1 20); do
    if rpc eth_chainId '[]' 2>/dev/null | grep -q '"result"'; then
        break
    fi
    sleep 0.5
    if ! kill -0 $ANVIL_PID 2>/dev/null; then
        echo "--- last 20 lines of $LOG_FILE ---" >&2
        tail -20 "$LOG_FILE" >&2
        die "anvil exited during startup; see $LOG_FILE"
    fi
done
log "anvil up (pid=$ANVIL_PID)"

# ── Activate features ────────────────────────────────────────────────────────
# Anvil's --unlocked + anvil_impersonateAccount lets us send activate() calls
# from the admin address without needing its private key. Real-chain forks
# would substitute --private-key + a funded signer.

log "funding + impersonating activation admin…"
rpc anvil_setBalance "[\"$ACTIVATION_ADMIN\", \"0xffffffffffffffff\"]" > /dev/null
rpc anvil_impersonateAccount "[\"$ACTIVATION_ADMIN\"]" > /dev/null

for fid in "${FEATURE_IDS[@]}"; do
    if should_skip_activate "$fid"; then
        log "leaving feature un-activated: $(feature_name "$fid") $fid [SKIP_ACTIVATE]"
        continue
    fi
    log "activating feature $fid"
    out=$(cast send --rpc-url "http://localhost:$PORT" --from "$ACTIVATION_ADMIN" \
        --unlocked "$REGISTRY" "activate(bytes32)" "$fid" 2>&1) || \
        die "activation tx failed for $fid:\n$out"
    # status==1 line confirms inclusion + success
    echo "$out" | grep -E "^status\b" | head -1 >&2 || die "no status in cast send output for $fid"
done

# ── Run the test suite ────────────────────────────────────────────────────────

log "running forge test --fork-url http://localhost:$PORT $*"
cd "$REPO_ROOT"

# LIVE_PRECOMPILES skips BaseTest's vm.etch of the mocks at the precompile
# addresses (so calls dispatch to the real Rust impls). FOUNDRY_PROFILE=fork
# enables the [profile.fork] base=true setting (so forge's EVM installs the
# Base precompile set).
LIVE_PRECOMPILES=true FOUNDRY_PROFILE=fork \
    "$FORGE_BIN" test --fork-url "http://localhost:$PORT" "$@"
forge_exit=$?

log "forge test exited $forge_exit"
exit $forge_exit
