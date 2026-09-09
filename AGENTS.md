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

## Cutting releases

### Major vs. minor

Versioning is `vMAJOR.MINOR.PATCH`, decided by the breaking change test below — not by hardfork
boundaries. Hardforks here are additive by design, so most land as MINOR:

- **MAJOR**: an actual breaking change. Rare.
- **MINOR**: a hardfork's frozen interface, once it's additive (the common case) — increments once
  per hardfork, matching `changelog/README.md`'s [Hardfork ordinals](changelog/README.md#hardfork-ordinals)
  shifted down by one (`01` Beryl → `1.0`, `02` Cobalt → `1.1`, ...). Also covers any other additive
  change. Freezing happens at tag time, which can be before on-chain activation.
- **PATCH**: no interface change — tooling, harness, docs, or CI fixes (e.g. `v1.0.1`'s fork-profile
  pin).

If a hardfork's interface does contain a breaking change, that bumps MAJOR instead (resetting
MINOR/PATCH to `0`).

### Breaking change test

This repo's invariant is slot-for-slot storage parity with the Rust precompiles plus a stable
public ABI — a change is breaking if it violates either.

Fix an already-shipped selector and its inputs. If the outcome can differ from what it is today —
succeeds where it reverted, reverts where it succeeded, reverts with a different error, or
returns/emits something different — it's breaking, regardless of whether the ABI itself gained or
lost anything. A new error or event isn't automatically non-breaking; check what it's reachable from.

### Drafting a release

There is one ongoing release branch per MAJOR line, `releases/vN.x`, fast-forwarded to `main` at
each freeze point — no per-hardfork or per-minor branch. A new `releases/v(N+1).x` only gets cut the
day a breaking change actually ships.

1. Land the frozen interface, its `changelog/<ordinal>_<Hardfork>_*.md` entries, and the
   `CHANGELOG.md` summary on `main`.
2. Fast-forward `releases/vN.x` to that commit: `git push origin main:releases/vN.x`.
3. Tag from that branch, draft first: `git tag vN.M.P && git push origin vN.M.P`, then
   `gh release create vN.M.P --draft --notes-file <notes>` — a draft anchored to a real, pushed tag
   (GitHub shows a synthetic `untagged-<hash>` URL for drafts; expected, resolves on publish).
4. Write notes via `--notes-file` and proofread the rendered draft (`gh release view vN.M.P`) before
   leaving it — title/body follow `v1.0.0`/`v1.0.1`: compatibility statement, one bullet per
   changelog entry, link the aligned base/base tag if one exists.
5. Keep at most one open draft per version. If the branch moves before publishing, delete
   (`gh release delete vN.M.P --yes`) and re-tag rather than leaving a stale draft around.

## Boundaries

- **Don't change the precompile addresses** in `src/StdPrecompiles.sol` or the feature IDs in
  `script/smoke/config.py` / `test/lib/mocks/ActivationRegistryFeatureList.sol` — they are
  canonical constants shared with base/base; coordinate changes there first.
- **Don't reshape mock storage layout unilaterally** — match `MockB20Storage.sol` slot constants
  and cross-validate with `make fork-tests` before merging.
- **Don't commit `.env` or real private keys** — `.env` is gitignored; use funded testnet keys.
- **Don't introduce internal-only references** — this repo is public. No links or paths to non-public
  resources (internal wikis, private design docs, dashboards, chat), no internal ticket or
  audit-finding IDs, no internal codenames or handles — in code, comments, NatSpec, docs, or commit
  messages. Restate internal rationale inline in public terms instead of linking it; public EIP/ERC
  and GitHub URLs and `@author Coinbase` are fine. Remove any you find.
- **Don't hand-edit ABIs for the smoke tests** — `script/smoke/abis.py` loads them from `out/`;
  run `forge build` instead.
- **Don't weaken a slot-assertion test to make live-precompile tests pass** — investigate the divergence via
  `LIVE_PRECOMPILE_TESTING.md` and fix the side that's wrong.
