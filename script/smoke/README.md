# b20 precompile smoketest

A lightweight, dependency-thin smoketest that drives the b20 precompiles
(`B20Factory`, `B20Asset`, `B20Stablecoin`, `PolicyRegistry`) by sending **real
transactions to a live JSON-RPC endpoint**. It is the runbook check for
precompile bring-up: point it at a node where the b20 features are activated and
it walks the full operator lifecycle of each precompile, asserting balances,
events, and revert reasons against the real Rust implementation.

It is deliberately *not* a Foundry test. The harness is plain
[`web3.py`](https://web3py.readthedocs.io/) talking directly to RPC, so it has no
dependency on `forge`'s in-process EVM. The only thing it borrows from the build
is the **interface ABIs**, which it reads straight from `out/` after a
`forge build`, so the surface it binds to always matches the current source.

## What you need

The suite talks to a **real node over JSON-RPC** that has the b20 features
activated. It is not coupled to any particular node: a remote Base fork
(>= Beryl), or a node you run yourself (for example a local build of
[`base/base`](https://github.com/base/base)) both work, as long as the
precompiles are deployed and the features are switched on in the
ActivationRegistry. The suite does not stand a node up for you and does not fund
anyone for you: you supply the endpoint and two funded keys.

## Running

```bash
make smoke-setup                 # one-time: create the venv + install web3
cp .env.template .env            # then set RPC_URL, DEPLOYER_PK, USER2_PK
make smoke-all KEEP_GOING=1      # all journeys, audit summary; or one: make smoke-factory
```

`DEPLOYER_PK` must hold enough ether to sign the setup and admin txs (it also
sends `USER2_PK` a small one-time gas float). You are responsible for funding it:
on a real network you fund it yourself, or, if the chain has a faucet, set
`FAUCET_URL` + `FAUCET_NETWORK` in `.env` and the preflight tops the deployer up
when it falls below the floor. `foundry.toml` also defines fork RPC endpoints
(e.g. `vibenet`) you can point `RPC_URL` at, provided the features are activated
there.

`.env` is gitignored; the Makefile sources it for every smoke recipe and existing
shell env wins over `.env` values.

### Make targets

```bash
make smoke            # run every journey, fail-fast (CI gating default)
make smoke-all        # all journeys, single process, fail-fast
make smoke-all KEEP_GOING=1   # all journeys, summarize, exit 0 regardless
make smoke-factory    # one journey at a time: factory|asset|stablecoin|policy|invariants
make smoke-setup      # create the venv + install web3 (one-time)
```

> The `smoke-*` targets set `PYTHONPATH=script` for you. Running `python -m smoke`
> by hand needs that too (and the env exported), else you get `No module named
> smoke` — prefer the Make targets. The raw CLI takes an arbitrary subset and a
> fail-fast/keep-going flag, e.g. `python -m smoke asset policy -k`.

### Environment / config knobs

| Var | Required | Default | Meaning |
|---|---|---|---|
| `RPC_URL` | yes | — | JSON-RPC endpoint to send txs to. |
| `DEPLOYER_PK` | yes | — | Funded key that signs setup/admin txs. |
| `USER2_PK` | yes | — | Second actor (recipient / non-admin paths). |
| `GAS_FLOAT_ETHER` | no | `0.01` | One-time gas float the deployer sends user2. |
| `SMOKE_SALT` | no | random | Pin the per-run salt namespace (reproducible addresses). |
| `SMOKE_TRACE` | no | `1` | On failure, dump a `debug_traceCall/Transaction` call tree. Set `0` for just the request + replayed revert data. |
| `FAUCET_URL` / `FAUCET_NETWORK` | no | — | Optional deployer top-up when underfunded. |
| `FAUCET_AMOUNT` / `FAUCET_MIN_ETHER` | no | `0.05` / `0.02` | Faucet amount and balance floor. |

## What it checks

Five "journeys", each runnable on its own or all together:

| Journey | What it exercises |
|---|---|
| `factory` | Deterministic create + address prediction, the `isB20` / `isB20Initialized` query surface, and creation-time reverts (duplicate salt, bad decimals, bad currency, unknown variant). |
| `asset` | Full Asset-variant lifecycle (18 decimals): mint, transfer, `transferWithMemo`, delegated `transferFrom`, `announce` + `batchMint`, rebase via `updateMultiplier`, metadata, burn, then the gates that must reject (supply cap, pause, role, announcement-id reuse). |
| `stablecoin` | Stablecoin-variant deltas (fixed 6 decimals, immutable currency) plus the regulated freeze-and-seize path (blocklist policy + `burnBlocked`). |
| `policy` | Policy creation (both types), membership, built-in sentinels, the two-step admin transfer lifecycle, and a token actually *enforcing* a policy (`PolicyForbids` on transfer + mint). |
| `invariants` | EVM-context invariants a precompile must implement explicitly: payable rejection, unknown-selector revert, strict ABI decode, dirty-bit canonicalization, `STATICCALL` read-only enforcement, returndata fidelity, OOG containment, revert atomicity, and gas independence from a force-fed balance. Uses the `PrecompileProbe` + `ForceFeeder` helpers under `test/lib/`. |

Each lifecycle journey ends with a flow-level check that every expected event
type was emitted. The `invariants` journey is a *collect-all audit*: it runs
every check, reports findings at the end, and fails only if a required invariant
did not hold (see [Interpreting output](#interpreting-output)).

## Interpreting output

Per-step lines are prefixed `→` (step), `✓` (assertion passed), `✗` (failed).
Each journey logs `<name>: OK` on success. A run ends in one of three states per
journey:

- **pass** — all assertions held.
- **fail** — an assertion or expected revert did not match. For lifecycle
  journeys this is fail-fast; the harness dumps the offending call (and a trace
  when `SMOKE_TRACE=1`).
- **skip** — the preflight found the b20 features are **not activated** on the
  target chain. Reported as chain/fork state, *not* a contract defect:

  ```
  [smoke] b20 features NOT ACTIVE on chain <id>: ActivationRegistry not installed ... fork < Beryl?
  [smoke] ... skipping (use the ActivationRegistry to enable).
  ```

  If everything skips, your RPC simply doesn't have the precompiles active.
  Activate the b20 features in the ActivationRegistry, or point `RPC_URL` at a
  node that already has them.

The `invariants` journey is special: it collects all findings and prints
`N/12 invariants held`. A finding is a precompile behavior to triage, not a flaky
test. To accept a known divergence, add its check name to the `INFORMATIONAL` set
in `journeys/precompile_invariants.py` — it stays reported but no longer fails the
run.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No module named smoke` | Running outside `make`. Use the Make targets or export `PYTHONPATH=script`. |
| `RPC_URL did not answer` | Endpoint unreachable. Check the node is up and the URL/port. |
| Everything **skipped** | Target node doesn't have the b20 features active. Activate them in the ActivationRegistry, or point `RPC_URL` at a node that has them. |
| `deployer ... underfunded ... no faucet configured` | Fund `DEPLOYER_PK`, or set `FAUCET_URL` + `FAUCET_NETWORK`. |

## Package layout

```
script/smoke/
  __main__.py         # CLI: python -m smoke <journey ...> [-k]; preflight + dispatch
  config.py           # addresses, enum/role/feature constants, env -> Config
  chain.py            # web3 harness: send/read, revert + event assertions, RPC tracing
  abis.py             # interface ABIs + probe/feeder artifacts, read from out/
  codec.py            # the one hand-written encode: createB20 params + initCalls
  errors.py           # selector -> custom-error-name map (from the ABIs)
  journeys/           # factory, asset_lifecycle, stablecoin_lifecycle, policy_registry, precompile_invariants
  requirements.txt
```
