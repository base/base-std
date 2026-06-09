#!/usr/bin/env python3
"""
check-coverage.py

Runs forge coverage and checks that every function in the mock implementations
under test/lib/mocks/ has at least one test calling it. Uses the lcov report
as the source of truth rather than parsing Solidity files.

Usage:
  python3 script/check-coverage.py
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOCK_DIR = "test/lib/mocks/"
LCOV_PATH = ROOT / "lcov.info"


def generate_lcov() -> None:
    result = subprocess.run(
        [
            "forge",
            "coverage",
            "--no-match-coverage",
            r"(\.t\.sol|Test\.sol)$",
            "--report",
            "lcov",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("forge coverage failed:\n" + result.stderr, file=sys.stderr)
        sys.exit(1)


def parse_lcov() -> dict[str, list[str]]:
    """Return {source_file: [uncovered_fn, ...]} for mock files with 0-hit functions."""
    uncovered: dict[str, list[str]] = {}
    current_file: str | None = None
    fn_hits: dict[str, int] = {}

    for line in LCOV_PATH.read_text().splitlines():
        if line.startswith("SF:"):
            current_file = line[3:]
            fn_hits = {}
        elif line.startswith("FN:"):
            _, name = line[3:].split(",", 1)
            fn_hits.setdefault(name, 0)
        elif line.startswith("FNDA:"):
            count_str, name = line[5:].split(",", 1)
            fn_hits[name] = fn_hits.get(name, 0) + int(count_str)
        elif line == "end_of_record":
            if current_file and MOCK_DIR in current_file:
                zero = sorted(fn for fn, hits in fn_hits.items() if hits == 0)
                if zero:
                    uncovered[current_file] = zero
            current_file = None
            fn_hits = {}

    return uncovered


def main() -> int:
    generate_lcov()

    if not LCOV_PATH.exists():
        print("ERROR: lcov.info not found after forge coverage run", file=sys.stderr)
        return 1

    uncovered = parse_lcov()

    if uncovered:
        total = sum(len(fns) for fns in uncovered.values())
        print(f"Functions with no test coverage ({total}):")
        print()
        for source_file, fns in sorted(uncovered.items()):
            rel = source_file.replace(str(ROOT) + "/", "")
            for fn in fns:
                print(f"  {rel}: {fn}")
        return 1

    print("All interface functions have test coverage.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
