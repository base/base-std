# Fork testing: base-std vs Base Rust precompiles

> Agent / engineer handoff for revalidating base-std's Solidity reference
> against base/base's Rust precompile impls. Read this when the precompile
> code in `base/base` changes (or when you're picking the workflow up cold).

## What this does

Runs base-std's existing unit test suite (~346 tests with paired
`vm.load`-based slot assertions, from PR #43) against a **local node that
hosts Base's Rust precompiles** (`base-anvil`). Forge dispatches calls to
those precompiles instead of to base-std's Solidity mocks; the suite's
slot-level assertions then surface any divergence between the Solidity
reference and the Rust impl as a precise failure.

Failures are the cross-validation signal — each one tells you exactly which
storage slot / field encoding / packing scheme diverges.

## Architecture

```
base-std/                  base-anvil/                base/
└── test/unit/*.t.sol  ──→ └── target/.../forge   ──→ └── crates/common/
    (Solidity tests +          (foundry fork w/         precompiles/
     slot assertions)           --base flag)             (Rust impls)
                            └── target/.../base-anvil
                                (local node hosting
                                 the precompiles)
```

- **base-std** (this repo): tests + mocks. Unchanged from `main` except for
  `[profile.fork] base = true` in `foundry.toml` and the
  `LIVE_PRECOMPILES` skip-etch in `test/lib/BaseTest.sol`.
- **base-anvil** (`github.com/base/base-anvil`, fork of foundry-rs/foundry):
  one trait extension in anvil's `PrecompileFactory` + a `--base` flag
  added to `foundry-evm-networks` (~80 LOC of real change). The flag
  installs base/base's precompile set into both forge's and anvil's REVM.
- **base/base**: the Rust precompile crate (`crates/common/precompiles/`).
  base-anvil consumes it via a path dependency.

## Prerequisites (first-time setup)

Clone three repos as siblings:

```
~/code/
├── base/         ← github.com/base/base (any B-20-containing branch; default: main)
├── base-anvil/   ← github.com/base/base-anvil
└── base-std/     ← github.com/base/base-std (this repo)
```

If your layout differs, set `BASE_ANVIL_BIN` and `FORGE_BIN` env vars to
override the script's defaults.

Install Rust + the fast linker:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
brew install lld  # macOS; Linux uses mold per base-anvil's .cargo/config.toml
```

Build base-anvil and our patched forge (~30 min first build, incremental
after):

```bash
cd ~/code/base-anvil
cargo build --release -p base-anvil -p forge
```

## Run the tests

```bash
cd ~/code/base-std
./script/run-fork-tests.sh
```

The script:

1. Launches `base-anvil --base --base-activation-admin 0x9965507D...` on port 8546.
2. Funds + impersonates the activation admin, sends `activate(bytes32)` for
   each of the 4 gated features.
3. Runs `LIVE_PRECOMPILES=true FOUNDRY_PROFILE=fork forge test --fork-url
   http://localhost:8546`.
4. Tears down base-anvil.

Forward any `forge test` flag through the script:

```bash
./script/run-fork-tests.sh -vvvv --match-test test_transfer_success_debitsSender
```

## When the precompiles update — the loop

This is the main workflow. base/base's precompile crate changes; you want
fresh cross-validation against the new impl.

**Step 1: pull the new precompile code.**

```bash
cd ~/code/base
git checkout <branch>          # main usually; or a feature branch
git pull
```

Note any new precompile addresses, new feature IDs, or changed ABI in the
commit log. Skim
`base/crates/common/precompiles/src/activation/storage.rs` for new
`FEATURE_*` constants.

**Step 2: if new feature IDs were added**, append them to the
`FEATURE_IDS` array in `script/run-fork-tests.sh`. The script must activate
every gated feature before tests run; otherwise the feature's calls revert
`FeatureNotActivated`.

**Step 3: if new precompiles were added** (a new `*Precompile::install`
call appeared in `base/crates/common/precompiles/src/provider.rs`):

Update `base-anvil/crates/evm/networks/src/lib.rs`:

- Add the new install call in `NetworkConfigs::inject_precompiles`'s
  `if self.base { ... }` block, mirroring `BasePrecompiles::install`.
- Add label / address entries in `precompiles_label` and `precompiles`.
- Add the address constant at the top of the file if it's a new singleton.

**Step 4: rebuild base-anvil.**

```bash
cd ~/code/base-anvil
cargo build --release -p base-anvil -p forge
```

Cargo picks up the new `base-common-precompiles` source via the path dep.

**Step 5: rerun the test suite.**

```bash
cd ~/code/base-std
./script/run-fork-tests.sh
```

**Step 6: triage the deltas.** Compare against the last run's failure
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

## Common failure modes & fixes

**`base-anvil binary not found`** — run `cargo build --release -p base-anvil`
in `base-anvil/`. Or `BASE_ANVIL_BIN=/abs/path ./script/run-fork-tests.sh`.

**`port 8546 is already in use`** — `pkill -f "target/.*/base-anvil"` or
`PORT=8547 ./script/run-fork-tests.sh`.

**`base-anvil exited during startup`** — check `/tmp/base-anvil.log`. Usual
cause: rust build is stale after a base/base change; rebuild.

**Hundreds of `EvmError: Revert` with `gas: 0` in `setUp`** — either the
`LIVE_PRECOMPILES` env var wasn't set (BaseTest etched the mocks over the
precompile addresses) or `[profile.fork] base = true` is missing from
`foundry.toml` (forge isn't installing the precompiles). The script sets
both, but if you're invoking forge directly, set both.

**`FeatureNotActivated(bytes32)` revert payload** — a new gated feature
landed in base/base. Add its ID to `FEATURE_IDS` in
`script/run-fork-tests.sh`. The payload's 32-byte tail IS the feature ID
(grep `base/crates/common/precompiles/src/activation/storage.rs` for the
matching `FEATURE_*` constant).

**Cargo version conflicts when building base-anvil** — base/base bumped
its `revm` / `alloy-evm` / `alloy-primitives` versions away from what
base-anvil's foundry fork has. Edit `base-anvil/Cargo.toml` to match
base/base's versions (see existing fork-comments next to those entries).
Most version bumps inside the same major version are source-compatible.

**Everything reverts even with `--base` set** — verify the precompiles are
deployed by running base-anvil manually and probing:

```bash
~/code/base-anvil/target/release/base-anvil --base --port 8546 &
cast call 0x84530000000000000000000000000000000000ff "admin()(address)" --rpc-url http://localhost:8546
# Should return 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc.
```

If this returns garbage / fails, the base-anvil build is broken or out of
date.

## Where everything lives

| Thing | Path | Notes |
|---|---|---|
| The test runner script | `script/run-fork-tests.sh` | bash; takes forge args through `$@` |
| Forge profile config | `foundry.toml`, `[profile.fork]` | `base = true` enables Rust precompile dispatch |
| Skip-etch logic | `test/lib/BaseTest.sol` | guarded by `LIVE_PRECOMPILES` env var |
| Slot assertions | `test/unit/**/*.t.sol`, `test/lib/mocks/Mock*Storage.sol` | shipped in base-std PR #43 |
| Storage helpers | `test/lib/mocks/MockB20Storage.sol`, `MockPolicyRegistryStorage.sol` | the slot-derivation library every assertion uses |
| Patched forge + base-anvil | `~/code/base-anvil/target/.../{forge,base-anvil}` | built by `cargo build -p forge -p base-anvil` |
| `--base` flag implementation | `~/code/base-anvil/crates/evm/networks/src/lib.rs` | edit here when precompile set changes |
| Rust precompile source | `~/code/base/crates/common/precompiles/` | path-dep'd into base-anvil |
| Feature IDs | `~/code/base/crates/common/precompiles/src/activation/storage.rs` | `FEATURE_*` consts |
| ActivationRegistry default admin | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | codified in base/base PR #2811 |
| Vibenet chainid | 84538453 | auto-enables `--base` |

## What's NOT in scope

- **Calling the live vibenet RPC directly with `--fork-url
  https://rpc.vibes.base.org/`**. That can work, but vibenet's state may
  not have the features you need activated, and the activation admin is
  the real-chain key, not anvil's account 0. Use base-anvil locally for
  iteration; reserve live vibenet for final verification of features the
  team has already activated upstream.

- **Maintaining the foundry fork rebase against upstream foundry-rs**.
  That's base-anvil's `README.md` / `BUILDING.md`. This doc only covers
  the test-running side.

- **Activation admin key management for real-chain forks**. The default
  admin is the local-dev account; producing test transactions from the
  real activation admin on vibenet requires that key (which we don't
  have). Use `ACTIVATION_ADMIN=<addr>` + `--private-key` only if you have
  the key, otherwise stay on base-anvil.
