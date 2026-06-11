# Source the gitignored .env for the smoke recipes.
LOAD_ENV = pre=$$(export -p); set -a; [ -f .env ] && . ./.env; set +a; eval "$$pre";

# The smoke + fork runners require Python 3.13 (the version the shared venv is built and CI-tested
# against). `make smoke-setup` enforces this via `python-check` before creating the venv. Override the
# interpreter with `make smoke-setup PYTHON=/path/to/python3.13` if 3.13 isn't on your PATH as below.
REQUIRED_PYTHON = 3.13
PYTHON ?= python3.13
VENV = script/smoke/.venv
# `smoke` and `fork` are packages under script/, so script/ is on the path. Both share the one venv
# (web3 is their only dependency); `make smoke-setup` provisions it.
SMOKE_RUN = $(LOAD_ENV) PYTHONPATH=script $(VENV)/bin/python -m smoke
FORK_RUN = $(LOAD_ENV) PYTHONPATH=script $(VENV)/bin/python -m fork

.PHONY: build coverage smoke smoke-all smoke-factory smoke-asset smoke-stablecoin smoke-policy smoke-invariants python-check smoke-setup fork-tests

# Generate an lcov coverage report and open it in the browser.
# Scoped to src/ and test/lib/mocks/ (excludes test runner files and the smoke probe helper).
coverage:
	forge coverage --no-match-coverage "(\.t\.sol|Test\.sol|Probe\.sol)$$" --report lcov
	genhtml lcov.info --branch-coverage -o coverage --dark-mode --ignore-errors inconsistent,corrupt
	open coverage/index.html


# Verify the interpreter for the venv exists and is the required version. Runs before smoke-setup;
# prints install guidance and fails fast if Python $(REQUIRED_PYTHON) isn't available as $(PYTHON).
python-check:
	@command -v $(PYTHON) >/dev/null 2>&1 || { \
	  echo "ERROR: '$(PYTHON)' not found. The smoke + fork runners require Python $(REQUIRED_PYTHON)."; \
	  echo "Install it, then re-run (or pass PYTHON=/path/to/python$(REQUIRED_PYTHON)):"; \
	  echo "  pyenv:   pyenv install $(REQUIRED_PYTHON) && pyenv local $(REQUIRED_PYTHON)"; \
	  echo "  macOS:   brew install python@$(REQUIRED_PYTHON)"; \
	  echo "  Debian:  sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt-get install -y python$(REQUIRED_PYTHON) python$(REQUIRED_PYTHON)-venv"; \
	  exit 1; \
	}
	@$(PYTHON) -c 'import sys; req=tuple(int(x) for x in "$(REQUIRED_PYTHON)".split(".")); \
	  sys.exit(0) if sys.version_info[:len(req)] == req else \
	  sys.exit("ERROR: %s is Python %d.%d.%d, but this project requires Python $(REQUIRED_PYTHON).x. " \
	           "Install it or pass PYTHON=/path/to/python$(REQUIRED_PYTHON)." \
	           % ("$(PYTHON)", sys.version_info.major, sys.version_info.minor, sys.version_info.micro))'
	@echo "python-check: $(PYTHON) is $$($(PYTHON) --version 2>&1 | cut -d' ' -f2) (need $(REQUIRED_PYTHON).x) — ok"

# One-time setup: verify Python $(REQUIRED_PYTHON), then create the smoke+fork venv and install web3.
smoke-setup: python-check
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/python -m pip install -r script/smoke/requirements.txt

# Run the unit suite against a local anvil with Base's Rust precompiles, cross-validating the Solidity
# reference against the live Rust impl. Needs the patched anvil+forge from the base-anvil fork (see
# script/fork/__main__.py for env vars). Forward forge args via ARGS, e.g.
#   make fork-tests ARGS="-vvvv --match-test test_transfer_success_debitsSender"
#   make fork-tests ARGS="--match-contract PolicyRegistryDispatchInactive" SKIP_ACTIVATE=POLICY_REGISTRY
fork-tests:
	@$(FORK_RUN) $(ARGS)

# Compile the contracts.
build:
	forge build

# b20 precompile bring-up smoketest (web3.py + the interface ABIs read from
# `out/`). Sends real txs to $RPC_URL; requires env RPC_URL, DEPLOYER_PK,
# USER2_PK and a venv (`make smoke-setup`). `make smoke` runs every journey
# fail-fast.
smoke: smoke-factory smoke-asset smoke-stablecoin smoke-policy smoke-invariants

# Run every journey in a single process. KEEP_GOING=1 runs them all and reports a
# summary without erroring on failure (audit/triage mode); default fails fast and
# exits non-zero on the first failure (CI gating).
#   make smoke-all                # fail-fast
#   make smoke-all KEEP_GOING=1   # run all, report, exit 0
smoke-all: build
	@$(SMOKE_RUN) all $(if $(KEEP_GOING),--keep-going,)

smoke-factory: build
	@$(SMOKE_RUN) factory

smoke-asset: build
	@$(SMOKE_RUN) asset

smoke-stablecoin: build
	@$(SMOKE_RUN) stablecoin

smoke-policy: build
	@$(SMOKE_RUN) policy

smoke-invariants: build
	@$(SMOKE_RUN) invariants
