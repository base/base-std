"""python -m fork [forge test args...] — run the base-std unit suite against a
local anvil that dispatches Base's Rust precompiles, cross-validating the
Solidity reference against the live Rust impl.

Requires the patched anvil + forge from the base-anvil fork. Env vars, exit
codes, and the full workflow are documented in README.md.
"""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from web3 import Web3

# Feature ids: reuse the smoke package's derived keccak constants (one source of truth).
from smoke.config import (
    ACTIVATION_REGISTRY,
    FEATURE_B20_ASSET,
    FEATURE_B20_STABLECOIN,
    FEATURE_POLICY_REGISTRY,
)

# __main__.py -> fork -> script -> project root.
REPO_ROOT = Path(__file__).resolve().parents[2]

ENV_ERROR = 2  # environment-problem exit code.

# (name, id) in activation order; names are the SKIP_ACTIVATE / log labels.
FEATURES: list[tuple[str, bytes]] = [
    ("B20_ASSET", bytes(FEATURE_B20_ASSET)),
    ("POLICY_REGISTRY", bytes(FEATURE_POLICY_REGISTRY)),
    ("B20_STABLECOIN", bytes(FEATURE_B20_STABLECOIN)),
]

ACTIVATE_SELECTOR = bytes(Web3.keccak(text="activate(bytes32)")[:4])
DEACTIVATE_SELECTOR = bytes(Web3.keccak(text="deactivate(bytes32)")[:4])
ISACTIVATED_SELECTOR = bytes(Web3.keccak(text="isActivated(bytes32)")[:4])


def log(msg: str) -> None:
    print(f"[run-fork-tests] {msg}", file=sys.stderr)


def die(msg: str) -> "NoReturn":  # noqa: F821 - NoReturn quoted to avoid a typing import
    print(f"[run-fork-tests] ERROR: {msg}", file=sys.stderr)
    raise SystemExit(ENV_ERROR)


# ── Binary discovery ────────────────────────────────────────────────────────────


def _executable(path: Path) -> bool:
    return path.is_file() and os.access(path, os.X_OK)


def discover_binaries() -> tuple[Path, Path]:
    """Resolve (anvil, forge) from $ANVIL_BIN/$FORGE_BIN or the base-anvil default layout."""
    anvil_env = os.environ.get("ANVIL_BIN")
    if anvil_env:
        anvil = Path(anvil_env)
    else:
        release = REPO_ROOT / ".." / "base-anvil" / "target" / "release" / "anvil"
        debug = REPO_ROOT / ".." / "base-anvil" / "target" / "debug" / "anvil"
        if _executable(release):
            anvil = release
        elif _executable(debug):
            anvil = debug
        else:
            die(
                "anvil binary not found. Expected at:\n"
                f"  {release}\n  {debug}\n"
                "Build with: cd ../base-anvil && cargo build --release -p anvil -p forge\n"
                "Or set ANVIL_BIN=/path/to/anvil."
            )

    forge = Path(os.environ.get("FORGE_BIN") or anvil.parent / "forge")
    if not _executable(forge):
        die(
            f"patched forge binary not found at {forge}.\n"
            f"Build with: cd {anvil.parent.parent.parent} && cargo build --release -p forge\n"
            "Or set FORGE_BIN=/path/to/forge.\n"
            "(System forge will NOT work — it lacks the --base injection. forge must come from "
            "the base-anvil fork of foundry-rs.)"
        )
    return anvil, forge


# ── SKIP_ACTIVATE parsing ────────────────────────────────────────────────────────


def skip_set() -> set[str]:
    """Uppercased SKIP_ACTIVATE entries (feature names or 0x ids), whitespace-stripped, empties dropped."""
    raw = os.environ.get("SKIP_ACTIVATE", "")
    return {entry.strip().upper() for entry in raw.split(",") if entry.strip()}


def should_skip(name: str, fid: bytes, skip: set[str]) -> bool:
    """True if a feature is named in SKIP_ACTIVATE by its canonical name or its raw 0x id (case-insensitive)."""
    return name.upper() in skip or f"0X{fid.hex().upper()}" in skip


# ── Anvil lifecycle ──────────────────────────────────────────────────────────────


def assert_port_free(port: int) -> None:
    """Die if something is already listening on the RPC port (mirrors the bash lsof guard)."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        if sock.connect_ex(("127.0.0.1", port)) == 0:
            die(f"port {port} is already in use. Set PORT=<other> or kill the existing listener.")


@contextmanager
def anvil_running(anvil: Path, port: int, admin: str, log_path: Path) -> Iterator[Web3]:
    """Launch anvil --base, yield a Web3 once the RPC is live, and tear it down on exit (any outcome)."""
    with open(log_path, "w") as logf:
        proc = subprocess.Popen(
            [str(anvil), "--base", "--base-activation-admin", admin, "--port", str(port)],
            stdout=logf,
            stderr=subprocess.STDOUT,
        )
    try:
        w3 = Web3(Web3.HTTPProvider(f"http://localhost:{port}"))
        for _ in range(20):  # poll for the RPC port to come up (up to 10s)
            if proc.poll() is not None:
                tail = "".join(log_path.read_text().splitlines(keepends=True)[-20:])
                die(f"anvil exited during startup; see {log_path}\n--- last 20 lines of {log_path} ---\n{tail}")
            try:
                if w3.eth.chain_id:
                    break
            except Exception:  # noqa: BLE001 - RPC not up yet; keep polling
                pass
            time.sleep(0.5)
        else:
            die(f"anvil did not answer RPC within 10s; see {log_path}")
        log(f"anvil up (pid={proc.pid})")
        yield w3
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


# ── Activation ───────────────────────────────────────────────────────────────────


def _is_activated(w3: Web3, fid: bytes) -> bool:
    """Read ActivationRegistry.isActivated(fid) via eth_call (no tx)."""
    ret = w3.eth.call({"to": ACTIVATION_REGISTRY, "data": Web3.to_hex(ISACTIVATED_SELECTOR + fid)})
    return int.from_bytes(bytes(ret), "big") != 0


def reconcile_feature_state(w3: Web3, admin: str, skip: set[str]) -> None:
    """Bring each gated feature to the state this run needs, idempotently.

    Works whether the node boots with features inactive (plain `anvil --base`)
    or already seeded active (`anvil --base` once base-anvil BOP-375 lands):
    non-skipped features are ensured active, SKIP_ACTIVATE features are ensured
    inactive so the inactive-dispatch path is exercised either way. Activating
    an already-active feature reverts AlreadyActivated, so we check first.
    """
    log("funding + impersonating activation admin…")
    w3.provider.make_request("anvil_setBalance", [admin, hex(2**64 - 1)])
    w3.provider.make_request("anvil_impersonateAccount", [admin])

    for name, fid in FEATURES:
        want_active = not should_skip(name, fid, skip)
        if _is_activated(w3, fid) == want_active:
            log(f"feature {name} 0x{fid.hex()} already {'active' if want_active else 'inactive'}")
            continue
        selector = ACTIVATE_SELECTOR if want_active else DEACTIVATE_SELECTOR
        verb = "activating" if want_active else "deactivating"
        log(f"{verb} feature {name} 0x{fid.hex()}")
        data = Web3.to_hex(selector + fid)
        try:
            tx_hash = w3.eth.send_transaction({"from": admin, "to": ACTIVATION_REGISTRY, "data": data})
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        except Exception as exc:  # noqa: BLE001 - any RPC/tx failure is an environment problem
            die(f"{verb} tx failed for {name} 0x{fid.hex()}: {type(exc).__name__}: {exc}")
        if receipt["status"] != 1:
            die(f"{verb} tx reverted for {name} 0x{fid.hex()} (status {receipt['status']})")


# ── Orchestration ────────────────────────────────────────────────────────────────


def main(forge_args: list[str]) -> int:
    port = int(os.environ.get("PORT", "8546"))
    admin = Web3.to_checksum_address(
        os.environ.get("ACTIVATION_ADMIN", "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc")
    )
    log_path = Path(os.environ.get("ANVIL_LOG", "/tmp/anvil.log"))
    skip = skip_set()

    anvil, forge = discover_binaries()
    assert_port_free(port)

    log(f"anvil:            {anvil}")
    log(f"forge:            {forge}")
    log(f"port:             {port}")
    log(f"activation admin: {admin}")
    log(f"log file:         {log_path}")
    log(f"skip-activate:    {os.environ.get('SKIP_ACTIVATE') or '<none>'}")

    log("starting anvil…")
    with anvil_running(anvil, port, admin, log_path) as w3:
        reconcile_feature_state(w3, admin, skip)

        rpc_url = f"http://localhost:{port}"
        log(f"running forge test --fork-url {rpc_url} {' '.join(forge_args)}")
        # LIVE_PRECOMPILES: skip the mock etch; fork profile: base=true installs the precompiles.
        env = {**os.environ, "LIVE_PRECOMPILES": "true", "FOUNDRY_PROFILE": "fork"}
        result = subprocess.run(
            [str(forge), "test", "--fork-url", rpc_url, *forge_args],
            cwd=REPO_ROOT,
            env=env,
        )

    log(f"forge test exited {result.returncode}")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
