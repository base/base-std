"""CLI: python -m smoke <journey>.

Journeys: factory, asset, stablecoin, policy. Env (RPC_URL / DEPLOYER_PK /
USER2_PK) is sourced by the Makefile from .env; running directly requires it
exported. The target chain is assumed to already have the b20 features activated.
"""

from __future__ import annotations

import importlib
import sys

from . import config
from .chain import Chain, die, log

JOURNEYS = {
    "factory": "smoke.journeys.factory",
    "asset": "smoke.journeys.asset_lifecycle",
    "stablecoin": "smoke.journeys.stablecoin_lifecycle",
    "policy": "smoke.journeys.policy_registry",
}


def main(argv: list[str]) -> None:
    if len(argv) != 1 or argv[0] not in JOURNEYS:
        die(f"usage: python -m smoke <{'|'.join(JOURNEYS)}>")
    cfg = config.Config.from_env()
    chain = Chain(cfg)
    log(f"preflight ok \u2014 chain={chain.chain_id} deployer={chain.DEPLOYER}")
    log(f"run nonce: {cfg.run_nonce}" + (" (pinned via SMOKE_SALT)" if cfg.salt_pinned else ""))
    module = importlib.import_module(JOURNEYS[argv[0]])
    module.run(chain)


if __name__ == "__main__":
    main(sys.argv[1:])
