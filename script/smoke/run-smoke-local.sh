#!/usr/bin/env bash
# run-smoke-local.sh — one-command local smoketest against a base-anvil node.
#
# Stands up everything the b20 smoketest needs and tears it down again:
#   1. Launch a `--base` anvil (installs the b20 precompile suite into the EVM).
#   2. Activate the gated features via the ActivationRegistry (impersonating the
#      activation admin — no key needed on a local anvil).
#   3. Run the smoke suite with RPC_URL + two of anvil's PRE-FUNDED dev accounts,
#      so there is nothing to fund by hand.
#   4. Tear down anvil regardless of success / failure.
#
# This is the happy-path local runner. For a remote/shared chain, skip this and
# drive `make smoke-*` directly with your own RPC_URL + funded keys (see README).
#
# Any extra arguments are forwarded to the smoke CLI (journey names + flags):
#   ./script/smoke/run-smoke-local.sh                 # all journeys, summary, exit 0
#   ./script/smoke/run-smoke-local.sh factory         # just one journey, fail-fast
#   ./script/smoke/run-smoke-local.sh asset policy    # a subset
#
# Env vars (with defaults):
#   ANVIL_BIN   path to the patched `--base` anvil binary
#               (default: <repo>/../base-anvil/target/release/anvil, then debug)
#   PORT        local RPC port for anvil (default: 8546)
#   ANVIL_LOG   anvil stdout/stderr log path (default: /tmp/anvil-smoke.log)
#   PYTHON      python used to create the venv (default: python3.13)
#
# Note: only the patched ANVIL is needed here. The smoke harness talks to the
# node over RPC and reads ABIs from out/, so a stock `forge build` is enough — it
# does NOT need the patched forge that run-fork-tests.sh uses.
#
# Exit codes: 0 suite passed/skipped clean · non-zero suite failed · 2 setup error.

set -euo pipefail

# ── Layout ────────────────────────────────────────────────────────────────────
SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SMOKE_DIR/../.." && pwd)"
VENV="$SMOKE_DIR/.venv"

DEFAULT_ANVIL_RELEASE="$REPO_ROOT/../base-anvil/target/release/anvil"
DEFAULT_ANVIL_DEBUG="$REPO_ROOT/../base-anvil/target/debug/anvil"

PORT="${PORT:-8546}"
ACTIVATION_ADMIN="0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
REGISTRY=0x8453000000000000000000000000000000000001
LOG_FILE="${ANVIL_LOG:-/tmp/anvil-smoke.log}"
PYTHON="${PYTHON:-python3.13}"

# Standard anvil dev accounts (mnemonic "test test ... junk"), each pre-funded
# with 10000 ETH. Using them as the smoke signers means no manual funding on a
# local node. NEVER use these keys on a real network — they are public.
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # acct 0
USER2_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d     # acct 1

# Feature IDs mirror test/lib/mocks/ActivationRegistryFeatureList.sol.
FEATURE_IDS=(
    0xcdcc772fe4cbdb1029f822861176d09e646db96723d4c1e82ddfdeb8163ef54c  # B20_ASSET
    0xb582ebae03f16fee49a6763f78df482fb11ae73f103ed0d330bbe556aa90a43f  # POLICY_REGISTRY
    0xecfa0def2c10020caaf65e6155aa69c84b24892aaef76eeac52e0e2b3a0b8601  # B20_STABLECOIN
)

log() { echo "[smoke-local] $*" >&2; }
die() { echo "[smoke-local] ERROR: $*" >&2; exit 2; }

rpc() {
    curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}" \
        "http://127.0.0.1:$PORT"
}

# ── Resolve the patched anvil binary ───────────────────────────────────────────
if [[ -z "${ANVIL_BIN:-}" ]]; then
    if [[ -x "$DEFAULT_ANVIL_RELEASE" ]]; then
        ANVIL_BIN="$DEFAULT_ANVIL_RELEASE"
    elif [[ -x "$DEFAULT_ANVIL_DEBUG" ]]; then
        ANVIL_BIN="$DEFAULT_ANVIL_DEBUG"
    else
        echo "ERROR: base-anvil binary not found. Expected at:" >&2
        echo "  $DEFAULT_ANVIL_RELEASE" >&2
        echo "  $DEFAULT_ANVIL_DEBUG" >&2
        echo "Build it (see FORK_TESTING.md):" >&2
        echo "  cd ../base-anvil && cargo build --release -p anvil" >&2
        echo "Or point ANVIL_BIN=/abs/path/to/anvil at an existing build." >&2
        exit 2
    fi
fi

# ── Pre-flight ──────────────────────────────────────────────────────────────────
command -v cast  >/dev/null 2>&1 || die "cast not found (install foundry: https://getfoundry.sh)"
command -v forge >/dev/null 2>&1 || die "forge not found (install foundry: https://getfoundry.sh)"
command -v curl  >/dev/null 2>&1 || die "curl not found"
lsof -i ":$PORT" >/dev/null 2>&1 && die "port $PORT already in use. Set PORT=<other> or kill the listener."

# ── Ensure the python venv exists ───────────────────────────────────────────────
if [[ ! -x "$VENV/bin/python" ]]; then
    log "creating smoke venv (one-time)…"
    "$PYTHON" -m venv "$VENV"
    "$VENV/bin/python" -m pip install --quiet --upgrade pip
    "$VENV/bin/python" -m pip install --quiet -r "$SMOKE_DIR/requirements.txt"
fi

# ── Compile ABIs (stock forge is fine; precompiles live in the node) ────────────
log "forge build (compiling interface ABIs into out/)…"
( cd "$REPO_ROOT" && forge build >/dev/null )

log "anvil:            $ANVIL_BIN"
log "port:             $PORT"
log "activation admin: $ACTIVATION_ADMIN"
log "log file:         $LOG_FILE"

# ── Launch anvil ────────────────────────────────────────────────────────────────
log "starting --base anvil…"
"$ANVIL_BIN" --base --base-activation-admin "$ACTIVATION_ADMIN" --port "$PORT" \
    > "$LOG_FILE" 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null; wait $ANVIL_PID 2>/dev/null; true' EXIT

for _ in $(seq 1 20); do
    rpc eth_chainId '[]' 2>/dev/null | grep -q '"result"' && break
    sleep 0.5
    if ! kill -0 $ANVIL_PID 2>/dev/null; then
        echo "--- last 20 lines of $LOG_FILE ---" >&2; tail -20 "$LOG_FILE" >&2
        die "anvil exited during startup; see $LOG_FILE"
    fi
done
log "anvil up (pid=$ANVIL_PID)"

# ── Activate the gated features ──────────────────────────────────────────────────
log "funding + impersonating activation admin…"
rpc anvil_setBalance "[\"$ACTIVATION_ADMIN\", \"0xffffffffffffffff\"]" > /dev/null
rpc anvil_impersonateAccount "[\"$ACTIVATION_ADMIN\"]" > /dev/null
for fid in "${FEATURE_IDS[@]}"; do
    log "activating feature $fid"
    out=$(cast send --rpc-url "http://127.0.0.1:$PORT" --from "$ACTIVATION_ADMIN" \
        --unlocked "$REGISTRY" "activate(bytes32)" "$fid" 2>&1) \
        || die "activation tx failed for $fid:"$'\n'"$out"
    echo "$out" | grep -E "^status\b" | head -1 >&2 || die "no status in cast output for $fid"
done

# ── Run the smoke suite ──────────────────────────────────────────────────────────
# Default to every journey in audit mode (run all, summarize, exit 0) when no
# args are given; otherwise forward the caller's journeys/flags verbatim.
if [[ $# -eq 0 ]]; then
    set -- all --keep-going
fi

log "running smoke suite: $*"
RPC_URL="http://127.0.0.1:$PORT" DEPLOYER_PK="$DEPLOYER_PK" USER2_PK="$USER2_PK" \
    PYTHONPATH="$REPO_ROOT/script" "$VENV/bin/python" -m smoke "$@"
smoke_exit=$?

log "smoke suite exited $smoke_exit"
exit $smoke_exit
