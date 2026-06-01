#!/usr/bin/env python3
"""
check-coverage.py

Validates that every external function declared in base-std interface files
has a corresponding unit test file. Exits 1 if gaps are found.

Usage:
  python3 scripts/check-coverage.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Maps interface filename -> unit test subdirectory under test/unit/
INTERFACE_MAP = {
    "IB20.sol":               "B20",
    "IB20Security.sol":       "B20Security",
    "IB20Stablecoin.sol":     "B20Stablecoin",
    "IB20Factory.sol":        "B20Factory",
    "IPolicyRegistry.sol":    "PolicyRegistry",
    "IActivationRegistry.sol": "ActivationRegistry",
}

# Functions covered by a shared grouped test file rather than one file each.
# These are skipped by the per-function file check. Update this when a new
# constant is added to an interface and it belongs to an existing grouped test.
GROUPED: dict[str, set[str]] = {
    "B20": {
        # Role byte constants — covered by roles/roleConstants.t.sol
        "DEFAULT_ADMIN_ROLE", "MINT_ROLE", "BURN_ROLE", "BURN_BLOCKED_ROLE",
        "PAUSE_ROLE", "UNPAUSE_ROLE", "METADATA_ROLE",
        # Policy-slot constants — covered by policy tests
        "TRANSFER_SENDER_POLICY", "TRANSFER_RECEIVER_POLICY",
        "TRANSFER_EXECUTOR_POLICY", "MINT_RECEIVER_POLICY",
    },
    "B20Security": {
        # Role constant — covered by constants/roleConstants.t.sol
        "SECURITY_OPERATOR_ROLE", "BURN_FROM_ROLE",
        # Precision constant — covered by constants/precisionConstants.t.sol
        "WAD_PRECISION",
        # Policy constant — covered by constants/policyTypeConstants.t.sol
        "REDEEM_SENDER_POLICY",
    },
}

# Happy-path test file stem overrides for functions whose test file was named
# differently from the function (historical naming). Only affects the happy-path
# file; _revertOrder files always use the actual function name.
HAPPY_PATH_RENAMES: dict[str, dict[str, str]] = {
    "B20Factory": {
        "createB20":     "createToken",
        "getB20Address": "getTokenAddress",
    },
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_FUNC_RE = re.compile(
    r"function\s+(\w+)\s*\([^)]*\)\s*external\s*(view|pure)?",
    re.MULTILINE,
)


def extract_functions(sol_file: Path) -> list[dict]:
    text = sol_file.read_text()
    results = []
    for m in _FUNC_RE.finditer(text):
        results.append({
            "name": m.group(1),
            "view": m.group(2) in ("view", "pure"),
        })
    return results


def exists_in(test_dir: Path, stem: str) -> bool:
    return bool(list(test_dir.rglob(f"{stem}.t.sol")))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    interfaces_dir = ROOT / "src" / "interfaces"
    test_unit_dir = ROOT / "test" / "unit"

    gaps: list[str] = []

    for iface_file, contract_dir_name in INTERFACE_MAP.items():
        iface_path = interfaces_dir / iface_file
        if not iface_path.exists():
            print(f"WARNING: {iface_file} not found, skipping")
            continue

        test_dir = test_unit_dir / contract_dir_name
        if not test_dir.exists():
            gaps.append(
                f"[{contract_dir_name}] MISSING test directory: test/unit/{contract_dir_name}/"
            )
            continue

        grouped = GROUPED.get(contract_dir_name, set())
        renames = HAPPY_PATH_RENAMES.get(contract_dir_name, {})
        functions = extract_functions(iface_path)

        for fn in functions:
            name = fn["name"]
            if name in grouped:
                continue

            happy_stem = renames.get(name, name)
            if not exists_in(test_dir, happy_stem):
                gaps.append(
                    f"[{contract_dir_name}] MISSING happy-path  : {happy_stem}.t.sol"
                )

            # _revertOrder is required for every state-mutating function
            if not fn["view"]:
                if not exists_in(test_dir, f"{name}_revertOrder"):
                    gaps.append(
                        f"[{contract_dir_name}] MISSING revertOrder : {name}_revertOrder.t.sol"
                    )

    if gaps:
        print("Interface coverage gaps found:\n")
        for g in sorted(gaps):
            print(f"  {g}")
        print(f"\n{len(gaps)} gap(s). Add missing test files or update GROUPED/HAPPY_PATH_RENAMES in scripts/check-coverage.py.")
        return 1

    print("Coverage OK — all interface functions have test files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
