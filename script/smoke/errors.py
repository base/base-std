"""Selector -> custom-error-name map, derived from the interface ABIs.

`expect_revert` names a revert by matching the 4-byte selector in the revert
data (web3's ContractCustomError.data) against this map.
"""

from __future__ import annotations

from typing import Any

from web3 import Web3

from .abis import ALL_ABIS


def _signature(error: dict[str, Any]) -> str:
    types = ",".join(inp["type"] for inp in error.get("inputs", []))
    return f"{error['name']}({types})"


def _collect() -> dict[str, str]:
    out: dict[str, str] = {}
    for abi in ALL_ABIS:
        for entry in abi:
            if entry.get("type") == "error":
                selector = "0x" + Web3.keccak(text=_signature(entry))[:4].hex()
                out[selector.lower()] = entry["name"]
    return out


ERROR_BY_SELECTOR: dict[str, str] = _collect()
