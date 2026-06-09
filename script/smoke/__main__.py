"""CLI: python -m smoke <journey> [<journey> ...] [-k]

Journeys: factory, asset, stablecoin, policy, invariants — or `all` to run every
journey in sequence. Env (RPC_URL / DEPLOYER_PK / USER2_PK) is sourced by the
Makefile from .env; running directly requires it exported. A preflight liveness
probe checks the b20 precompiles are actually active on the target chain (fork
>= Beryl); if not, the journey is skipped rather than reporting environment state
(inactive feature → account-state fall-through) as contract defects.

Flags:
  -k, --keep-going   Run every selected journey even if one fails, print a summary,
                     and exit 0 regardless of failures. Without it the suite fails
                     fast and exits non-zero on the first failure (the default,
                     suitable for CI gating).
"""

from __future__ import annotations

import importlib
import sys

from . import config
from .chain import Chain, log

JOURNEYS = {
    "factory": "smoke.journeys.factory",
    "asset": "smoke.journeys.asset_lifecycle",
    "stablecoin": "smoke.journeys.stablecoin_lifecycle",
    "policy": "smoke.journeys.policy_registry",
    "invariants": "smoke.journeys.precompile_invariants",
}

# Canonical run order; also the expansion of `all`.
ORDER = ["factory", "asset", "stablecoin", "policy", "invariants"]


def _usage() -> str:
    return f"usage: python -m smoke <{'|'.join(ORDER)}|all> [more journeys ...] [-k|--keep-going]"


def _plan(argv: list[str]) -> tuple[list[str], bool]:
    """Parse argv into (ordered journey names, keep_going). Raises SystemExit on bad usage."""
    keep_going = False
    names: list[str] = []
    for arg in argv:
        if arg in ("-k", "--keep-going"):
            keep_going = True
        else:
            names.append(arg)

    if not names:
        raise SystemExit(f"[smoke] ERROR: {_usage()}")
    if "all" in names:
        return ORDER, keep_going
    unknown = [n for n in names if n not in JOURNEYS]
    if unknown:
        raise SystemExit(f"[smoke] ERROR: unknown journey(s): {', '.join(unknown)}\n{_usage()}")
    return [n for n in ORDER if n in names], keep_going


def main(argv: list[str]) -> None:
    selected, keep_going = _plan(argv)
    cfg = config.Config.from_env()

    results: list[tuple[str, str, str]] = []  # (name, status: pass|fail|skip, detail)
    for name in selected:
        chain = Chain(cfg)
        log(f"preflight ok \u2014 chain={chain.chain_id} block={chain.w3.eth.block_number} deployer={chain.DEPLOYER}")
        log(f"run nonce: {cfg.run_nonce}" + (" (pinned via SMOKE_SALT)" if cfg.salt_pinned else ""))
        chain.ensure_deployer_funded()
        active, why = chain.features_activated()
        if not active:
            log(f"b20 features NOT ACTIVE on chain {chain.chain_id}: {why}")
            log("Chain/fork-activation state, NOT a contract defect \u2014 skipping (use the ActivationRegistry to enable).")
            results.append((name, "skip", why))
            continue
        module = importlib.import_module(JOURNEYS[name])
        try:
            module.run(chain)
            results.append((name, "pass", ""))
        except SystemExit as exc:
            if not keep_going:
                raise
            results.append((name, "fail", str(exc.code or "").replace("[smoke] ERROR: ", "")))
        except Exception as exc:  # noqa: BLE001 - keep-going turns any journey crash into a recorded failure
            if not keep_going:
                raise
            results.append((name, "fail", f"{type(exc).__name__}: {exc}"))

    if not keep_going:
        return

    passed = sum(1 for _, status, _ in results if status == "pass")
    failed = [(n, d) for n, status, d in results if status == "fail"]
    skipped = [(n, d) for n, status, d in results if status == "skip"]
    log(f"smoke summary: {passed} passed, {len(failed)} failed, {len(skipped)} skipped (of {len(results)})")
    for name, detail in failed:
        log(f"  \u2717 {name} \u2014 {detail}")
    for name, detail in skipped:
        log(f"  \u2298 {name} \u2014 {detail}")
    # --keep-going asks the suite NOT to error on failure: report and exit 0.


if __name__ == "__main__":
    main(sys.argv[1:])
