"""Interface ABIs loaded straight from the Foundry build output (`out/`).

These are the strict contract surface the harness binds to via plain web3
(`w3.eth.contract(abi=...)`). They are read from the compiled artifacts under
`out/`, so they always match the current source — run `forge build` first (the
smoke Make targets do this for you). The `out/` tree is gitignored; nothing
here is committed or copied by hand.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

# abis.py -> smoke -> script -> project root, where forge writes `out/`.
_OUT = Path(__file__).resolve().parents[2] / "out"


def _artifact(name: str) -> dict[str, Any]:
    """Load the forge artifact for `<name>.sol/<name>.json` (errors if unbuilt)."""
    path = _OUT / f"{name}.sol" / f"{name}.json"
    if not path.exists():
        raise SystemExit(
            f"[smoke] ERROR: {path} missing; run `forge build` first "
            "(the smoke Make targets build automatically)"
        )
    return json.loads(path.read_text())


def _load(name: str) -> list[dict[str, Any]]:
    return _artifact(name)["abi"]


FACTORY_ABI = _load("IB20Factory")
ASSET_ABI = _load("IB20Asset")
STABLECOIN_ABI = _load("IB20Stablecoin")
POLICY_ABI = _load("IPolicyRegistry")

ALL_ABIS = [FACTORY_ABI, ASSET_ABI, STABLECOIN_ABI, POLICY_ABI]


def probe_artifact() -> tuple[list[dict[str, Any]], str]:
    """abi + creation bytecode for PrecompileProbe (compiled into `out/`).

    The probe is the one helper the harness deploys, so unlike the interface ABIs it needs bytecode
    too. Read straight from the forge artifact rather than a committed copy.
    """
    art = _artifact("PrecompileProbe")
    return art["abi"], art["bytecode"]["object"]


def forcefeeder_artifact() -> tuple[list[dict[str, Any]], str]:
    """abi + creation bytecode for ForceFeeder (compiled into `out/`).

    Deployed with a non-zero `value` to SELFDESTRUCT its balance into a target address — the
    unblockable ether push used by the force-fed-ether invariant check.
    """
    art = _artifact("ForceFeeder")
    return art["abi"], art["bytecode"]["object"]
