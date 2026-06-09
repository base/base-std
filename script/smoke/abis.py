"""Committed interface ABIs (extracted from forge `out/`).

These are the strict contract surface the harness binds to via plain web3
(`w3.eth.contract(abi=...)`). They change only when the interfaces change;
regenerate with `make smoke-bindings`.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_DIR = Path(__file__).parent / "abi"


def _load(name: str) -> list[dict[str, Any]]:
    return json.loads((_DIR / f"{name}.json").read_text())


FACTORY_ABI = _load("IB20Factory")
ASSET_ABI = _load("IB20Asset")
STABLECOIN_ABI = _load("IB20Stablecoin")
POLICY_ABI = _load("IPolicyRegistry")

ALL_ABIS = [FACTORY_ABI, ASSET_ABI, STABLECOIN_ABI, POLICY_ABI]
