# Live precompile testing: base-std vs Base Rust precompiles

> Agent / engineer handoff for revalidating base-std's Solidity reference
> against base/base's Rust precompile impls. Read this when the precompile
> code in `base/base` changes (or when you're picking the workflow up cold).

## Quick start (installed binaries)

Most devs don't need to build base-anvil from source. Install it alongside your
stock Foundry (it never touches your existing `forge`/`anvil`) to get
`base-forge` and `base-anvil`:

```bash
curl -L https://raw.githubusercontent.com/base/base-anvil/HEAD/foundryup/install | bash
base-foundryup
```

**In-process, no node — the common case.** `base-forge` hosts the precompiles
in `forge`'s own EVM and seeds the gated features active, so the suite just runs
and `BaseTest` auto-detects the live world:

```bash
base-forge test
```

`setUp` logs which world ran: **LIVE PRECOMPILE mode** (under `base-forge`) or
**REFERENCE mode** (stock `forge test`, exercising the Solidity mocks).

**Against a real base-anvil node — genuine fork testing.** Point the Python
runner at your installed binaries; it boots `anvil --base`, activates the gated
features, and runs `forge test --fork-url` against the node:

```bash
make smoke-setup   # one-time: Python 3.13 venv + web3
ANVIL_BIN="$HOME/.foundry/versions/base-nightly/anvil" \
FORGE_BIN="$HOME/.foundry/versions/base-nightly/forge" \
  make fork-tests
```

> A base-anvil **node** starts with the gated features **inactive** — it mirrors
> a real chain, where only the activation admin flips features on. (Forge's
> in-process `--base` is the exception: it seeds them active for the no-node
> path above.) `make fork-tests` activates them for you; if you start a node by
> hand, activate via the admin first or calls revert `FeatureNotActivated` (see
> "When the precompiles update" below).

Build base-anvil from source only if you're changing base-anvil itself — see
the from-source setup below.

## What this does

Runs base-std's existing unit test suite (~346 tests with paired
`vm.load`-based slot assertions) against a **local node that
hosts Base's Rust precompiles** (the patched `anvil` from the base-anvil
fork). Forge dispatches calls to those precompiles instead of to base-std's
Solidity mocks; the suite's slot-level assertions then surface any
divergence between the Solidity reference and the Rust impl as a precise
failure.

Failures are the cross-validation signal — each one tells you exactly which
storage slot / field encoding / packing scheme diverges.

## Architecture

```
base-std/                  base-anvil/                base/
└── test/unit/*.t.sol  ──→ └── target/.../forge   ──→ └── crates/common/
    (Solidity tests +          (foundry fork w/         precompiles/
     slot assertions)           --base flag)             (Rust impls)
                            └── target/.../anvil
                                (same fork's anvil
                                 binary; --base flag
                                 hosts precompiles)
```

- **base-std** (this repo): tests + mocks. Unchanged from `main` except for
  `[profile.fork] base = true` in `foundry.toml` and the
  `LIVE_PRECOMPILES` skip-etch in `test/lib/BaseTest.sol`.
- **base-anvil** (`github.com/base/base-anvil`, fork of foundry-rs/foundry):
  a single `--base` flag added to `foundry-evm-networks::NetworkConfigs`,
  reached by both `forge` and `anvil` through their shared CLI flatten.
  Installs base/base's precompile set into the EVM. Build produces stock
  `forge` and `anvil` binaries with the flag baked in.
- **base/base**: the Rust precompile crate (`crates/common/precompiles/`).
  The base-anvil fork consumes it as a git dep pinned to a specific commit,
  not as a sibling-path clone. The pinned commit lives in
  `base-anvil/crates/evm/networks/Cargo.toml` and is updated via
  `base-anvil/script/bump-base.sh`. A local base/base clone is only needed
  if you want to iterate on an unpushed branch (see "Local-iteration
  override" below).

## Building base-anvil from source (contributors)

> Only needed if you're modifying base-anvil itself. Most devs should use the
> installed binaries from [Quick start](#quick-start-installed-binaries) above.

Clone two repos as siblings (base/base is fetched automatically by cargo):

```
~/code/
├── base-anvil/   ← github.com/base/base-anvil
└── base-std/     ← github.com/base/base-std (this repo)
```

If your layout differs, set `ANVIL_BIN` and `FORGE_BIN` env vars to
override the runner's defaults.

Install Rust + the fast linker, plus stock foundry (for `cast`):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
brew install lld  # macOS; Linux uses mold per base-anvil's .cargo/config.toml
curl -L https://foundry.paradigm.xyz | bash && foundryup  # stock foundry, for `cast` (the manual probe below)
```

The runner itself is Python ([`script/fork/`](script/fork/)), driven by `web3`
and requiring **Python 3.13**. Create its venv once (shared with the smoke
suite; `make smoke-setup` checks the version and prints install guidance if it's
missing):

```bash
make smoke-setup
```

Build the patched forge + anvil (~30 min first build, incremental after).
Cargo fetches the pinned base/base commit from github on first build:

```bash
cd ~/code/base-anvil
cargo build --release -p anvil -p forge
```

## Run the tests

The simplest path needs no node and no flags — `base-forge` (from the
base-anvil fork) hosts the live precompiles in-process and `BaseTest`
auto-detects them:

```bash
base-forge test
```

`setUp` prints which world it ran in: **LIVE PRECOMPILE mode** (checking
base/base against the Solidity reference) under `base-forge`, or **REFERENCE
mode** (exercising the Solidity mocks; base/base not under test) under stock
`forge test`. No `LIVE_PRECOMPILES` or `FOUNDRY_PROFILE=fork` needed —
detection is a behavioral probe of the precompile addresses.

To cross-validate against a **real base-anvil node** (the original harness,
used in CI), use the Python runner, which boots `anvil --base`, activates the
gated features, and runs `forge test --fork-url` against it:

```bash
cd ~/code/base-std
make fork-tests
```

The runner ([`script/fork/`](script/fork/)):

1. Launches `anvil --base --base-activation-admin 0x9965507D...` on port 8546.
2. Funds + impersonates the activation admin, sends `activate(bytes32)` for
   each of the gated features.
3. Runs `LIVE_PRECOMPILES=true FOUNDRY_PROFILE=fork forge test --fork-url
   http://localhost:8546`.
4. Tears down anvil.

Forward any `forge test` flag through `ARGS`:

```bash
make fork-tests ARGS="-vvvv --match-test test_transfer_success_debitsSender"
```

## Exercising the inactive-feature dispatch path

By default the script activates every gated feature before `forge test`, so the
suite never sees a feature in its inactive state. To cross-validate the
dispatcher's *inactive* behavior (error semantics must not depend on whether a
feature is active), set `SKIP_ACTIVATE` to a comma-separated list of feature
names (or raw `0x` ids) to leave un-activated:

```bash
SKIP_ACTIVATE=POLICY_REGISTRY make fork-tests \
    ARGS="--match-contract PolicyRegistryDispatchInactive"
```

The inactive-dispatch tests (`test/unit/PolicyRegistry/dispatch_inactive.t.sol`)
also normalize the feature to inactive themselves, so they're correct under the
default run too; `SKIP_ACTIVATE` additionally validates the never-activated
baseline. One assertion (that an unknown selector is classified *before* the
activation gate rather than masked by `FeatureNotActivated`) encodes a fix that
isn't in the Rust impl yet, so it's gated behind `POLICY_DISPATCH_FIX`:

```bash
SKIP_ACTIVATE=POLICY_REGISTRY POLICY_DISPATCH_FIX=true make fork-tests \
    ARGS="--match-contract PolicyRegistryDispatchInactive"
```

Run it that way against a build that carries the dispatch-ordering fix (e.g. via
the [patch] local-clone override below) to enforce the regression; leave it
unset against stock builds so the default run stays green.

## When the precompiles update — the loop

This is the main workflow. base/base's precompile crate changes; you want
fresh cross-validation against the new impl.

**Step 1: retarget base-anvil at the new commit and rebuild.**

```bash
cd ~/code/base-anvil
./script/bump-base.sh                  # pin to current main HEAD + rebuild
./script/bump-base.sh sk/tangor        # pin to a branch HEAD + rebuild
./script/bump-base.sh 6fcce780144b...  # pin to an explicit commit + rebuild
./script/bump-base.sh --no-build main  # update Cargo.toml only
```

The script resolves the ref via `git ls-remote`, rewrites the pinned `rev`
in `crates/evm/networks/Cargo.toml`, and rebuilds `anvil` + `forge` unless
`--no-build` is passed.

Skim the new commits for new precompile addresses, feature IDs, or ABI
changes (`crates/common/precompiles/src/activation/storage.rs` for
`FEATURE_*` constants).

**Step 2: if new feature IDs were added**, add them to the derived feature set
the runner activates: the canonical `FEATURE_*` keccak constants in
[`script/smoke/config.py`](script/smoke/config.py) and the `FEATURES` table in
[`script/fork/__main__.py`](script/fork/__main__.py) (which reuses those
constants). The runner must activate every gated feature before tests run;
otherwise the feature's calls revert `FeatureNotActivated`.

**Step 3: if new precompiles were added** (a new `*Precompile::install`
call appeared in `base/crates/common/precompiles/src/provider.rs`):

Update `base-anvil/crates/evm/networks/src/lib.rs`:

- Add the new install call in `NetworkConfigs::inject_precompiles`'s
  `if self.base { ... }` block, mirroring `BasePrecompiles::install`.
- Add label / address entries in `precompiles_label` and `precompiles`.
- Add the address constant at the top of the file if it's a new singleton.

Then rerun `./script/bump-base.sh <ref>` to rebuild against the new pin.

**Step 4: rerun the test suite.**

```bash
cd ~/code/base-std
make fork-tests
```

**Step 5: triage the deltas.** Compare against the last run's failure
buckets. Resolved failures = improvements. New failures = regressions or
new divergences in the Rust impl. Bucket categories to expect (from the
v0 run):

| Bucket | What it means |
|---|---|
| `EvmError: Revert` (generic) | setUp or unexpected revert — dig in with `-vvvv` |
| `balances[X] slot must reflect ...` | Rust impl writes balance to a different slot |
| `allowances[X][Y] slot ...` | Allowance derivation diverges |
| `totalSupply slot ...` | Slot 3 ≠ where Rust stores totalSupply |
| `supplyCap slot ...` | Different slot |
| `currency field slot ...` | Stablecoin currency at different namespace/offset |
| `symbol / name / contractURI field slot ...` | String slot encoding diverges |
| `pausedVectors bit ...` | Pause-bitmap layout diverges |
| `transferSenderPolicyId / mintReceiverPolicyId lane ...` | Packed policy lane positions differ |
| `call didn't revert at a lower depth` | Rust impl accepts what mock rejects (or vice versa) |

Each divergence belongs to one of:

- **Rust impl bug** — fix in base/base, redo step 1.
- **Solidity reference / spec bug** — fix in base-std (update mock or
  storage library), reopen the alignment discussion.
- **Test bug** — fuzz input pathology, mock-only assumption that doesn't
  hold for the live impl, etc.; fix the test.

## Local-iteration override (unpushed base/base branches)

When you're iterating on a base/base branch that isn't pushed yet, or when
you need to apply an unmerged patch to the pinned commit (e.g. the current
`dispatch.rs` ActivationFeature::B20Stablecoin fix), the git-pin in
`base-anvil/crates/evm/networks/Cargo.toml` won't reach your local changes.

Use cargo's `[patch]` mechanism to redirect the dep to a local clone.
Edit `base-anvil/Cargo.toml`, find the commented `[patch."https://github.com/base/base.git"]`
block, and uncomment it (adjusting the path if needed):

```toml
[patch."https://github.com/base/base.git"]
base-common-precompiles = { path = "../base/crates/common/precompiles" }
base-common-chains = { path = "../base/crates/common/chains" }
```

Then `cd ~/code/base-anvil && cargo build --release -p anvil -p forge`. Cargo
uses the local path instead of the pinned remote commit. Re-comment the
block when you're done iterating.

## Common failure modes & fixes

**`anvil binary not found`** — run `cargo build --release -p anvil` in
`base-anvil/`. Or `ANVIL_BIN=/abs/path make fork-tests`.

**`port 8546 is already in use`** — `pkill -f "base-anvil/target/.*/anvil"`
or `PORT=8547 make fork-tests`.

**`anvil exited during startup`** — check `/tmp/anvil.log`. Usual cause:
rust build is stale after a base/base change; rebuild.

**Hundreds of `EvmError: Revert` / `cannot use precompile ... as an argument`
in `setUp`** — `BaseTest` tried to etch the mocks over live precompile
addresses. Auto-detection prevents this under `base-forge` or a `--fork-url`
node; if you still hit it, the precompiles aren't actually present (e.g.
`base = true` / `--base` missing, so forge isn't installing them). Force the
intended world with `LIVE_PRECOMPILES=true` if detection is ever wrong.

**`FeatureNotActivated(bytes32)` revert payload** — a new gated feature
landed in base/base. Add its ID to the derived feature set (see Step 2 above:
`FEATURE_*` in `script/smoke/config.py` + the `FEATURES` table in
`script/fork/__main__.py`). The payload's 32-byte tail IS the feature ID
(grep `base/crates/common/precompiles/src/activation/storage.rs` for the
matching `FEATURE_*` constant).

**Build fails with `error[E0599]: no variant or associated item named B20_STABLECOIN`
in `b20_stablecoin/dispatch.rs`** — you bumped past base/base commit
`d7662c05e` ("replace feature id constants with ActivationFeature
enum"). That refactor removed `ActivationRegistryStorage::B20_STABLECOIN`
but the call site in `dispatch.rs` still references it. Until upstream
fixes this, either pin the dep back to a pre-d7662c05e commit (e.g.
`./script/bump-base.sh 6fcce780144b31da208809161e4f9f2bd936c3de`) or apply
the one-line workaround via a local clone + the `[patch]` block (see
"Local-iteration override" above), changing the line to
`.ensure_activated(crate::ActivationFeature::B20Stablecoin.id())?;`.

**Cargo version conflicts when building the fork** — base/base bumped its
`revm` / `alloy-evm` / `alloy-primitives` versions away from what
base-anvil's foundry fork has. Edit `base-anvil/Cargo.toml` to match
base/base's versions (see existing fork-comments next to those entries).
Most version bumps inside the same major version are source-compatible.

**Everything reverts even with `--base` set** — verify the precompiles are
deployed by running anvil manually and probing:

```bash
~/code/base-anvil/target/release/anvil --base --port 8546 &
cast call 0x8453000000000000000000000000000000000001 "admin()(address)" --rpc-url http://localhost:8546
# Should return 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc.
```

If this returns garbage / fails, the fork's build is broken or out of date.

## Where everything lives

| Thing | Path | Notes |
|---|---|---|
| The test runner | `script/fork/` (`make fork-tests`) | Python + web3; forwards forge args through `ARGS` |
| Forge profile config | `foundry.toml`, `[profile.fork]` | `base = true` enables Rust precompile dispatch |
| Mode detection / skip-etch | `test/lib/BaseTest.sol` | auto-probes for live precompiles; `LIVE_PRECOMPILES=true` forces live |
| Slot assertions | `test/unit/**/*.t.sol`, `test/lib/mocks/Mock*Storage.sol` | `vm.load`-based slot-layout assertions paired with surface tests |
| Storage helpers | `test/lib/mocks/MockB20Storage.sol`, `MockPolicyRegistryStorage.sol` | the slot-derivation library every assertion uses |
| Patched forge + anvil | `~/code/base-anvil/target/.../{forge,anvil}` | built by `cargo build -p forge -p anvil` |
| `--base` flag implementation | `~/code/base-anvil/crates/evm/networks/src/lib.rs` | edit here when precompile set changes |
| base/base git pin | `~/code/base-anvil/crates/evm/networks/Cargo.toml` | the `rev = "..."` line, bumped via `./script/bump-base.sh` |
| Local-iteration override | `~/code/base-anvil/Cargo.toml` | commented `[patch."https://github.com/base/base.git"]` block |
| Rust precompile source | `github.com/base/base`, pinned commit | fetched by cargo on build; optional local clone for [patch] |
| Feature IDs | `base/crates/common/precompiles/src/activation/storage.rs` (on github) | `FEATURE_*` consts |
| ActivationRegistry default admin | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | the canonical local-dev admin |
| Vibenet chainid | 84538453 | auto-enables `--base` |

## What's NOT in scope

- **Calling the live vibenet RPC directly with `--fork-url
  https://rpc.vibes.base.org/`**. That can work, but vibenet's state may
  not have the features you need activated, and the activation admin is
  the real-chain key, not anvil's account 0. Use the patched anvil locally
  for iteration; reserve live vibenet for final verification of features
  the team has already activated upstream.

- **Maintaining the foundry fork rebase against upstream foundry-rs**.
  That's base-anvil's `README.md` / `BUILDING.md`. This doc only covers
  the test-running side.

- **Activation admin key management for real-chain forks**. The default
  admin is the local-dev account; producing test transactions from the
  real activation admin on vibenet requires that key (which we don't
  have). Use `ACTIVATION_ADMIN=<addr>` + `--private-key` only if you have
  the key, otherwise stay on the local patched anvil.
