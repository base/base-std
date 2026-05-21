#!/usr/bin/env bash
# run-fork-tests.sh — run the base-std unit suite against base-anvil's local
# Rust precompile dispatch, validating the Solidity reference against the live
# Rust impl from base/base.
#
# Workflow:
#   1. Launch base-anvil on $PORT with --base (registers Base precompiles).
#   2. Fund + impersonate the activation admin, activate the 4 gated features.
#   3. Run the patched forge with --fork-url against base-anvil + the `fork`
#      profile (which sets base = true so forge's EVM also dispatches).
#   4. Tear down base-anvil regardless of success / failure.
#
# Any extra arguments to this script are forwarded to `forge test`. Use them
# to scope the run (e.g. --match-contract, --match-test, -vvvv).
#
# Env vars (with defaults):
#   BASE_ANVIL_BIN   path to the patched base-anvil binary
#                    (default: ../base-anvil/target/release/base-anvil, then
#                    falls back to debug if release is missing)
#   FORGE_BIN        path to the patched forge binary
#                    (default: mirrors BASE_ANVIL_BIN's directory, looking for
#                    `forge` next to `base-anvil`)
#   PORT             local RPC port for base-anvil (default: 8546)
#   ACTIVATION_ADMIN address authorized to activate features
#                    (default: 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, the
#                    canonical local-dev admin codified in base/base#2811)
#
# Exit codes:
#   0   forge test exit 0 (all targeted tests pass)
#   1   forge test exit non-zero (at least one targeted test fails — the
#       output is the cross-validation signal)
#   2   environment problem (missing binary, port in use, base-anvil failed
#       to start, activation tx failed)

set -euo pipefail

# ── Layout ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_BASE_ANVIL_RELEASE="$REPO_ROOT/../base-anvil/target/release/base-anvil"
DEFAULT_BASE_ANVIL_DEBUG="$REPO_ROOT/../base-anvil/target/debug/base-anvil"

if [[ -z "${BASE_ANVIL_BIN:-}" ]]; then
    if [[ -x "$DEFAULT_BASE_ANVIL_RELEASE" ]]; then
        BASE_ANVIL_BIN="$DEFAULT_BASE_ANVIL_RELEASE"
    elif [[ -x "$DEFAULT_BASE_ANVIL_DEBUG" ]]; then
        BASE_ANVIL_BIN="$DEFAULT_BASE_ANVIL_DEBUG"
    else
        echo "ERROR: base-anvil binary not found. Expected at:" >&2
        echo "  $DEFAULT_BASE_ANVIL_RELEASE" >&2
        echo "  $DEFAULT_BASE_ANVIL_DEBUG" >&2
        echo "Build with: cd ../base-anvil && cargo build --release -p base-anvil" >&2
        echo "Or set BASE_ANVIL_BIN=/path/to/base-anvil." >&2
        exit 2
    fi
fi

if [[ -z "${FORGE_BIN:-}" ]]; then
    FORGE_BIN="$(dirname "$BASE_ANVIL_BIN")/forge"
    if [[ ! -x "$FORGE_BIN" ]]; then
        echo "ERROR: patched forge binary not found at $FORGE_BIN." >&2
        echo "Build with: cd $(dirname "$BASE_ANVIL_BIN")/../.. && cargo build --release -p forge" >&2
        echo "Or set FORGE_BIN=/path/to/forge." >&2
        echo "(System forge will NOT work — it lacks the --base injection." >&2
        echo " forge must come from the base-anvil fork of foundry-rs.)" >&2
        exit 2
    fi
fi

PORT="${PORT:-8546}"
ACTIVATION_ADMIN="${ACTIVATION_ADMIN:-0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc}"
REGISTRY=0x84530000000000000000000000000000000000ff
LOG_FILE="${BASE_ANVIL_LOG:-/tmp/base-anvil.log}"

# Feature IDs from base/base/crates/common/precompiles/src/activation/storage.rs.
# If a new feature is added there, append its ID here.
FEATURE_IDS=(
    0xceff857b4173841a3aef07ca52b183282fe74fe117e8f9dda0dcb3ddafd18a5b  # TOKEN_FACTORY
    0x47a1afe8d3d691b87e090ee972d223a11f4da971ff5416c04985bb2393aca752  # B20_TOKEN
    0xb582ebae03f16fee49a6763f78df482fb11ae73f103ed0d330bbe556aa90a43f  # POLICY_REGISTRY
    0x89e4523f0886ce01d76094212ed707081da92a45221e22c15c5689be470db63e  # SECURITIES_TOKEN_CREATION
)

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[run-fork-tests] $*" >&2; }
die()  { echo "[run-fork-tests] ERROR: $*" >&2; exit 2; }

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

log "base-anvil:       $BASE_ANVIL_BIN"
log "forge:            $FORGE_BIN"
log "port:             $PORT"
log "activation admin: $ACTIVATION_ADMIN"
log "log file:         $LOG_FILE"

# ── Launch base-anvil ─────────────────────────────────────────────────────────

log "starting base-anvil…"
"$BASE_ANVIL_BIN" --base --base-activation-admin "$ACTIVATION_ADMIN" --port "$PORT" \
    > "$LOG_FILE" 2>&1 &
BA_PID=$!
trap 'kill $BA_PID 2>/dev/null; wait $BA_PID 2>/dev/null; true' EXIT

# Poll for the RPC port to come up (up to 10s).
for i in $(seq 1 20); do
    if rpc eth_chainId '[]' 2>/dev/null | grep -q '"result"'; then
        break
    fi
    sleep 0.5
    if ! kill -0 $BA_PID 2>/dev/null; then
        echo "--- last 20 lines of $LOG_FILE ---" >&2
        tail -20 "$LOG_FILE" >&2
        die "base-anvil exited during startup; see $LOG_FILE"
    fi
done
log "base-anvil up (pid=$BA_PID)"

# ── Activate features ────────────────────────────────────────────────────────
# Anvil's --unlocked + anvil_impersonateAccount lets us send activate() calls
# from the admin address without needing its private key. Real-chain forks
# would substitute --private-key + a funded signer.

log "funding + impersonating activation admin…"
rpc anvil_setBalance "[\"$ACTIVATION_ADMIN\", \"0xffffffffffffffff\"]" > /dev/null
rpc anvil_impersonateAccount "[\"$ACTIVATION_ADMIN\"]" > /dev/null

for fid in "${FEATURE_IDS[@]}"; do
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
