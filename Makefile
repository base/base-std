.PHONY: coverage smoke smoke-factory smoke-asset smoke-stablecoin smoke-policy

# Generate an lcov coverage report and open it in the browser.
# Scoped to src/ and test/lib/mocks/ (excludes test runner files).
coverage:
	forge coverage --no-match-coverage "(\.t\.sol|Test\.sol)$$" --report lcov
	genhtml lcov.info --branch-coverage -o coverage --dark-mode --ignore-errors inconsistent,corrupt
	open coverage/index.html

# b20 precompile bring-up smoketest. cast-driven; sends real txs to $RPC_URL.
# Requires env: RPC_URL, DEPLOYER_PK, USER2_PK (see script/smoke/smoke-lib.sh).
# `make smoke` runs every journey fail-fast; the per-journey targets run one.
smoke: smoke-factory smoke-asset smoke-stablecoin smoke-policy

smoke-factory:
	./script/smoke/factory.sh

smoke-asset:
	./script/smoke/asset-lifecycle.sh

smoke-stablecoin:
	./script/smoke/stablecoin-lifecycle.sh

smoke-policy:
	./script/smoke/policy-registry.sh
