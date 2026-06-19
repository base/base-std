# AGENTS.md

Solidity interfaces, libraries, and reference mocks for Base's precompiles: **B20** (ERC-20 superset
with roles, policies, pausing, permits, memos), **PolicyRegistry** (allowlist/blocklist singleton),
and **ActivationRegistry** (feature flags). The Solidity mocks must mirror the Rust implementations
in base/base **slot-for-slot** — storage layout parity is the core invariant of this repo.

## Commands

```bash
forge build                          # compile (solc 0.8.30)
forge test -v                        # unit tests against mocked precompiles (fast; run first)
forge test -v --match-test <name>    # one test; --match-contract <name> for one suite
forge fmt                            # format Solidity (CI gates on `forge fmt --check`)
python3 script/check-coverage.py     # every interface function has a test (CI gate)
make coverage                        # lcov + HTML report (needs genhtml)

base-forge test                      # same suite vs the real Rust precompiles, in-process (no node); auto-detects
make smoke-setup                     # one-time venv setup — requires Python 3.13 exactly
make smoke-all                       # live-RPC smoke journeys (needs .env; see below)
make fork-tests                      # same suite vs a real base-anvil node (CI harness; patched anvil/forge)
```

Test tiers, in the order to reach for them: **unit** (mocks, no network) → **live precompile**
(real Rust precompiles — in-process via `base-forge test`, or vs a node via `make fork-tests`;
cross-validates layout/behavior) → **smoke** (real txs against a live chain).

## Testing

- Unit tests live in `test/unit/{Feature}/{Name}.t.sol`; names follow
  `test_{function}_{outcome}_{variant}`, e.g. `test_allowance_success_zeroByDefault`.
- Tests assert precompile storage directly via `vm.load` against the slot constants in
  `test/lib/mocks/MockB20Storage.sol`. **A live-precompile failure with passing unit tests means the
  Solidity reference and the Rust impl have diverged** — see `LIVE_PRECOMPILE_TESTING.md`, don't just
  patch the test.
- Live-precompile tests need the patched binaries from
  [base/base-anvil](https://github.com/base/base-anvil); **stock forge/anvil will not work**. Install
  them alongside stock Foundry with `base-foundryup` (it never touches your `forge`/`anvil`). Common
  path — in-process, no node: `base-forge test`; `BaseTest` auto-detects and `setUp` logs **LIVE
  PRECOMPILE mode** vs **REFERENCE mode**. CI/node path: `make fork-tests` boots `anvil --base` and
  activates the gated features for you (override the binaries with `ANVIL_BIN` / `FORGE_BIN`). Pass
  forge args via `make fork-tests ARGS="-vvvv --match-test <name>"`. Details:
  `LIVE_PRECOMPILE_TESTING.md`, `script/fork/README.md`.
- Smoke tests need `.env` (copy `.env.template`): `RPC_URL`, `DEPLOYER_PK`, `USER2_PK` —
  **testnet keys only**, both accounts funded. Journeys **skip (not fail)** when the target chain
  hasn't activated the feature — a skip is not a pass. Run one journey with
  `make smoke-{factory,asset,stablecoin,policy,invariants}`; audit mode:
  `make smoke-all KEEP_GOING=1`.
- Fuzz runs: 256 default, 10 under `FOUNDRY_PROFILE=fork` (RPC round-trips are slow).

## Project structure

```
src/StdPrecompiles.sol    # canonical precompile addresses + typed handles
src/interfaces/           # IB20, IB20Asset, IB20Stablecoin, IB20Factory, IPolicyRegistry, IActivationRegistry
src/lib/                  # B20Constants (role/policy ids), B20FactoryLib (createB20 encoders)
src/impls/                # reserved for reference impls (currently empty; mocks fill that role)
test/unit/                # one directory per feature; slot-level assertions
test/regression/          # interface renames/removals guard (B20Renames.t.sol, B20Removals.t.sol)
test/lib/                 # BaseTest.sol, B20Test.sol, mocks/ (reference behavior + storage layout)
script/smoke/             # Python 3.13 live-node smoketest (web3.py); see script/smoke/README.md
script/fork/              # node-based live-precompile runner (anvil + patched forge); see script/fork/README.md
docs/                     # specs: docs/B20/README.md, docs/PolicyRegistry/, docs/ActivationRegistry/
```

Deeper reading: `LIVE_PRECOMPILE_TESTING.md` (cross-validation architecture), `docs/B20/README.md` (B20 spec).

## Code style

- Solidity formatting comes from `foundry.toml`: 120-char lines, 4-space tabs, double quotes,
  long int types (`uint256`, never `uint`). Run `forge fmt` before committing.
- Interfaces use pragma `>=0.8.20 <0.9.0` (consumer compatibility); test/mock code uses `^0.8.20`,
  compiled with the pinned solc 0.8.30 from `foundry.toml`.
- Errors are custom types with parameters, e.g. `error InvalidSupplyCap(uint256 currentSupply,
  uint256 proposedCap)` — never `require` strings.
- Import via the public remappings `base-std/=src/` and `base-std-test/=test/`.
- Mock state uses ERC-7201 namespaced storage; new state must follow the same pattern.
- Python (`script/`): 3.13, PEP 8, snake_case functions, frozen dataclasses for config.
  `web3>=7.6,<8` is the only dependency; both runners share `script/smoke/.venv`.

## Git workflow

- **`main` is the default branch.** Branch from `main` and open PRs against `main`.
- Conventional Commits with optional scope: `feat(b20): ...`, `fix(smoke): ...`, `test:`, `docs:`,
  `chore:`. Put the rationale in the body, not just the what.
- CI on every PR: `forge build`, `forge test`, `forge fmt --check`,
  `python3 script/check-coverage.py`, coverage comment. Live-precompile tests run in a separate workflow.

## Boundaries

- **Don't change the precompile addresses** in `src/StdPrecompiles.sol` or the feature IDs in
  `script/smoke/config.py` / `test/lib/mocks/ActivationRegistryFeatureList.sol` — they are
  canonical constants shared with base/base; coordinate changes there first.
- **Don't reshape mock storage layout unilaterally** — match `MockB20Storage.sol` slot constants
  and cross-validate with `make fork-tests` before merging.
- **Don't commit `.env` or real private keys** — `.env` is gitignored; use funded testnet keys.
- **Don't hand-edit ABIs for the smoke tests** — `script/smoke/abis.py` loads them from `out/`;
  run `forge build` instead.
- **Don't weaken a slot-assertion test to make live-precompile tests pass** — investigate the divergence via
  `LIVE_PRECOMPILE_TESTING.md` and fix the side that's wrong.
