# fork-test runner

`python -m fork [forge test args...]` runs the base-std unit suite against a
**local anvil that dispatches Base's Rust precompiles**, cross-validating the
Solidity reference against the live Rust impl from `base/base`. It is the Python
port of the former `script/run-fork-tests.sh`.

Both binaries (anvil + forge) must come from the **base-anvil fork** of
foundry-rs, which adds a `--base` flag that installs the B-20 precompile suite
into the EVM. Stock foundry binaries will not work.

## What it does

1. Discovers the patched `anvil` + `forge` (env override or the base-anvil
   `target/release` → `target/debug` default layout).
2. Launches anvil on `$PORT` with `--base`, waits for the RPC to come up, and
   tears it down on exit (pass, fail, or crash).
3. Funds + impersonates the activation admin and calls
   `ActivationRegistry.activate(bytes32)` for each gated feature.
4. Runs `forge test --fork-url` under `FOUNDRY_PROFILE=fork` +
   `LIVE_PRECOMPILES=true`, forwarding any extra args, and propagates forge's
   exit code.

The gated feature ids are **derived** (`keccak` of the canonical feature names)
by importing them from the sibling [`smoke` package's `config.py`](../smoke/config.py),
so there is a single source of truth shared with the smoketest — no hand-kept
hex table to drift from the Solidity `ActivationRegistryFeatureList` / Rust
`storage.rs`.

## Running

Requires **Python 3.13** (`make smoke-setup` enforces it; override with `PYTHON=`).

```bash
make smoke-setup          # one-time: create the shared venv + install web3 (shared with `make smoke`)

make fork-tests                                                   # whole suite
make fork-tests ARGS="-vvvv --match-test test_transfer_success"  # scope + verbosity
make fork-tests ARGS="--match-contract PolicyRegistryDispatchInactive" SKIP_ACTIVATE=POLICY_REGISTRY
```

Or directly (the Makefile just sources `.env` and sets `PYTHONPATH=script`):

```bash
PYTHONPATH=script script/smoke/.venv/bin/python -m fork --match-test test_transfer_success
```

## Environment

| Var | Default | Meaning |
| --- | --- | --- |
| `ANVIL_BIN` | `../base-anvil/target/release/anvil` (→ `debug`) | patched anvil binary |
| `FORGE_BIN` | `forge` next to `ANVIL_BIN` | patched forge binary |
| `PORT` | `8546` | local RPC port for anvil |
| `ACTIVATION_ADMIN` | `0x9965…A4dc` | address authorized to activate features |
| `ANVIL_LOG` | `/tmp/anvil.log` | anvil stdout/stderr log path |
| `SKIP_ACTIVATE` | _(none)_ | comma-separated feature names or `0x` ids to leave un-activated (exercises the inactive-feature dispatch path); matched case-insensitively |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | all targeted tests pass |
| `1` | at least one targeted test fails — the output **is** the cross-validation signal |
| `2` | environment problem (missing binary, port in use, anvil failed to start, activation tx failed) |
