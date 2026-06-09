.PHONY: coverage smoke smoke-all smoke-factory smoke-asset smoke-stablecoin smoke-policy smoke-invariants smoke-setup smoke-bindings

# Generate an lcov coverage report and open it in the browser.
# Scoped to src/ and test/lib/mocks/ (excludes test runner files and the smoke probe helper).
coverage:
	forge coverage --no-match-coverage "(\.t\.sol|Test\.sol|Probe\.sol)$$" --report lcov
	genhtml lcov.info --branch-coverage -o coverage --dark-mode --ignore-errors inconsistent,corrupt
	open coverage/index.html

# Source the gitignored .env (shell-style, not Make-native) for the smoke
# recipes. Existing env wins: snapshot exports, source, then re-apply.
LOAD_ENV = pre=$$(export -p); set -a; [ -f .env ] && . ./.env; set +a; eval "$$pre";

PYTHON ?= python3.13
VENV = script/smoke/.venv
# `smoke` is the package at script/smoke/, so its parent (script) is on the path.
SMOKE_RUN = $(LOAD_ENV) PYTHONPATH=script $(VENV)/bin/python -m smoke

# One-time setup: create the smoketest venv and install web3.
smoke-setup:
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/python -m pip install -r script/smoke/requirements.txt

# Refresh the committed interface ABIs from the compiled artifacts. Only needed
# when the interfaces change (the harness binds to these via plain web3). Also
# emits the PrecompileProbe artifact (abi + bytecode) the invariants journey deploys.
smoke-bindings:
	forge build
	@for c in IB20Factory IB20Asset IB20Stablecoin IPolicyRegistry; do \
	  jq '.abi' "out/$$c.sol/$$c.json" > "script/smoke/abi/$$c.json" && echo "refreshed $$c.json"; \
	done
	@jq '{abi: .abi, bytecode: .bytecode.object}' out/PrecompileProbe.sol/PrecompileProbe.json \
	  > script/smoke/abi/PrecompileProbe.json && echo "refreshed PrecompileProbe.json"

# b20 precompile bring-up smoketest (web3.py + committed interface ABIs). Sends
# real txs to $RPC_URL; requires env RPC_URL, DEPLOYER_PK, USER2_PK and a venv
# (`make smoke-setup`). `make smoke` runs every journey fail-fast.
smoke: smoke-factory smoke-asset smoke-stablecoin smoke-policy smoke-invariants

# Run every journey in a single process. KEEP_GOING=1 runs them all and reports a
# summary without erroring on failure (audit/triage mode); default fails fast and
# exits non-zero on the first failure (CI gating).
#   make smoke-all                # fail-fast
#   make smoke-all KEEP_GOING=1   # run all, report, exit 0
smoke-all:
	@$(SMOKE_RUN) all $(if $(KEEP_GOING),--keep-going,)

smoke-factory:
	@$(SMOKE_RUN) factory

smoke-asset:
	@$(SMOKE_RUN) asset

smoke-stablecoin:
	@$(SMOKE_RUN) stablecoin

smoke-policy:
	@$(SMOKE_RUN) policy

smoke-invariants:
	@$(SMOKE_RUN) invariants
