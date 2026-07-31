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

`RPC_URL` may point at a **single node or a load-balanced pool of many nodes** (a
live network typically fronts dozens of backends at slightly different heights).
The harness handles the multi-node case transparently — see
[Multi-node consistency](#multi-node-consistency) — so you can run the same suite
against a local single node and a live pooled endpoint without changes.

## Running

Requires **Python 3.13** (`make smoke-setup` enforces it; override with `PYTHON=`).

```bash
make smoke-setup                 # one-time: create the venv + install web3
cp .env.template .env            # then set RPC_URL, DEPLOYER_PK, USER2_PK
make smoke KEEP_GOING=1          # run the full suite, audit summary
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
make smoke                 # run the FULL suite, fail-fast (CI gating default)
make smoke KEEP_GOING=1    # full suite, summarize, exit 0 regardless (audit/triage)
make smoke-all             # alias of `make smoke` (also honors KEEP_GOING)
make smoke-setup           # create the venv + install web3 (one-time)
```

The suite always runs as a whole — there are deliberately **no per-journey `make`
targets**, so you can't get false confidence from a partial run. For ad-hoc
single-journey debugging (cheaper and faster on a live chain, where every journey
spends real gas and time), call the CLI directly — it takes an arbitrary subset and
a fail-fast/keep-going flag:

```bash
PYTHONPATH=script python -m smoke asset            # one journey
PYTHONPATH=script python -m smoke asset policy -k  # a subset, keep-going
```

> `PYTHONPATH=script` is required (the Make targets set it for you); without it you
> get `No module named smoke`.

### Environment / config knobs

| Var | Required | Default | Meaning |
|---|---|---|---|
| `RPC_URL` | yes | — | JSON-RPC endpoint to send txs to. |
| `DEPLOYER_PK` | yes | — | Funded key that signs setup/admin txs. |
| `USER2_PK` | yes | — | Second actor (recipient / non-admin paths). |
| `GAS_FLOAT_ETHER` | no | `0.01` | One-time gas float the deployer sends user2. |
| `SMOKE_SALT` | no | random | Pin the per-run salt namespace (reproducible addresses). |
| `SMOKE_TRACE` | no | `1` | On failure, dump a `debug_traceCall/Transaction` call tree. Set `0` for just the request + replayed revert data. |
| `SMOKE_OBSERVE_FLIP` | no | `0` | `multiplier` journey: also observe the scheduled multiplier's lazy flip via a bounded real-time poll (off by default — real-time coupling would flap on a slow chain; pending state is asserted read-only regardless). |
| `SMOKE_FLIP_WINDOW_S` / `SMOKE_FLIP_TIMEOUT_S` | no | `30` / `150` | When `SMOKE_OBSERVE_FLIP=1`: how far in the future to schedule the flip, and how long to poll for it. |
| `FAUCET_URL` / `FAUCET_NETWORK` | no | — | Optional deployer top-up when underfunded. |
| `FAUCET_AMOUNT` / `FAUCET_MIN_ETHER` | no | `0.05` / `0.02` | Faucet amount and balance floor. |

### Advisory CI against Vibenet

`.github/workflows/smoke-tests.yml` runs the **full suite** against a live Base network on demand. It
is **`workflow_dispatch` only** — deliberately not wired to pull requests, merge groups, or a schedule.
Vibenet is a live chain that is manually deployed per hardfork, so CI can't guarantee which precompile
set is live; an automated run would flap. The workflow is **advisory and never gates merges**: run it
by hand (Actions → *Base Std Smoke Tests (Vibenet)* → *Run workflow*) after a hardfork ships. Its only
input is the RPC endpoint (default `https://rpc.vibes.base.org/`); it always runs every journey (`-k`)
against the ref you dispatch from — latest is `main`, and to run an older fork you dispatch from the
matching branch/tag (branch-per-fork; there is no journey picker and no fork/ref selector). It exports
`RPC_URL` from the input and `DEPLOYER_PK` / `USER2_PK` from repo secrets (`SMOKE_DEPLOYER_PK` /
`SMOKE_USER2_PK`), then reports per-journey **passed / failed / skipped** plus the chain id in the run
summary. A journey whose surface the live chain does not yet ship is reported as *skipped*, not failed.

## What it checks

Seven "journeys", run as a whole suite (a single journey can still be run via the CLI for debugging):

| Journey | What it exercises |
|---|---|
| `factory` | Deterministic create + address prediction, the `isB20` / `isB20Initialized` query surface, and creation-time reverts (duplicate salt, bad decimals, bad currency, unknown variant). |
| `asset` | Full Asset-variant lifecycle (18 decimals): mint, transfer, `transferWithMemo`, delegated `transferFrom`, `announce` + `batchMint`, rebase via `updateMultiplier`, metadata, burn, then the gates that must reject (supply cap, pause, role, announcement-id reuse). The rebase event is fork-aware (V1 `MultiplierUpdated` vs Cobalt `UIMultiplierUpdated`). |
| `multiplier` | ERC-8056 scheduled multiplier (AssetV2 @ Cobalt): `setUIMultiplier` scheduling + its guards (`InvalidMultiplier`, `EffectiveAtInPast`, `EffectiveAtTooFar`, `ScheduleOverlap`), `cancelScheduledMultiplier` (+ `NoScheduledMultiplier`), the `updateMultiplier` instant-failsafe V2 event semantics (`UIMultiplierUpdated` + `MultiplierUpdateCancelled`, *not* `MultiplierUpdated`), the read aliases (`uiMultiplier`/`balanceOfUI`/`totalSupplyUI`), and ERC-165 advertisement. **Skips** cleanly on a pre-Cobalt chain (probed via `supportsInterface(0xa60bf13d)`). |
| `stablecoin` | Stablecoin-variant deltas (fixed 6 decimals, immutable currency) plus the regulated freeze-and-seize path (blocklist policy + `burnBlocked`). |
| `seize` | Transfer-based seize (AssetV2 @ Cobalt): the `SEIZE_HOLDER_POLICY` membership gate + `SEIZE_ROLE`, `seizeWithMemo` (`Transfer` -> `Memo` -> `Seized`, supply-preserving), its reject gates (`AccountNotSeizable`, role, `InvalidReceiver`, `ContractPaused`), the admin-op decoupling from the receiver policy on `to`, and the independent `SEIZE` pause vector. **Skips** cleanly on a pre-Cobalt chain (probed via the `SEIZE_HOLDER_POLICY()` getter). Complements `stablecoin`, which covers the legacy burn-based `burnBlocked`. |
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
- **skip** — reported as chain/fork state, *not* a contract defect. Two cases:

  1. The preflight found the b20 features are **not activated** on the target chain:

     ```
     [smoke] b20 features NOT ACTIVE on chain <id>: ActivationRegistry not installed ... fork < Beryl?
     [smoke] ... skipping (use the ActivationRegistry to enable).
     ```

     If everything skips, your RPC simply doesn't have the precompiles active.
     Activate the b20 features in the ActivationRegistry, or point `RPC_URL` at a
     node that already has them.

  2. A journey's surface only exists on a **later fork** than the target chain — e.g. the
     `multiplier` journey against a pre-Cobalt chain (the ERC-8056 scheduled multiplier is
     AssetV2 @ Cobalt). It probes `supportsInterface(0xa60bf13d)` and opts out:

     ```
     [smoke] multiplier: not applicable on chain <id> — Asset does not advertise ERC-8056 ... pre-Cobalt
     ```

     Point `RPC_URL` at a chain on the fork that ships the surface (branch-per-fork: run the
     matching base-std ref).

The `invariants` journey is special: it collects all findings and prints
`N/12 invariants held`. A finding is a precompile behavior to triage, not a flaky
test. To accept a known divergence, add its check name to the `INFORMATIONAL` set
in `journeys/precompile_invariants.py` — it stays reported but no longer fails the
run.

## Multi-node consistency

A live RPC endpoint is usually a **load balancer in front of many nodes** that sit
at slightly different block heights (we measured ~1–2 blocks of spread on a live
pool). The pool is sticky *per connection* but routes *new* connections to
arbitrary backends. The journeys are serial — write, then immediately read the
result — so a naive harness can confirm a write on one backend and then have the
follow-up read routed to a backend that hasn't imported that block yet, observing
**pre-write state**. The classic symptom is `isB20Initialized == false`
immediately after a `createB20` that already succeeded.

`ConsistentHTTPProvider` (in `chain.py`) gives the whole run a single
read-your-writes view over the pool, with two layered mechanisms:

1. **Sticky connection (steady state).** The provider holds one keep-alive
   connection open for the run, pinning every request to a single backend that is
   trivially consistent with its own writes — no waiting, no retries.
2. **High-water safety net (on reconnect).** It tracks the highest block any
   confirmed receipt / head query revealed and pins every **state read**
   (`eth_call`, `eth_getBalance`, `eth_getCode`, `eth_getStorageAt`, gas
   estimation) to that block. If the connection drops and the pool re-pins us to a
   lagging backend, that backend answers `block not found` (rather than silently
   serving stale state); the provider drops the connection to force a re-route and
   retries until a synced backend answers, or it gives up after ~30s and surfaces
   the node's error.

The **nonce is deliberately not pinned** — it must reflect the account's *latest*
head, not a historical snapshot, or the broadcast is rejected as `nonce too low`.
Instead `Chain.next_nonce` reads the pending count and takes the max with a local
monotonic counter, so every signed tx gets a unique, forward-only nonce regardless
of which backend answered.

The net effect: a read never observes state older than a write the suite has
already confirmed, and nonces never collide or regress, no matter which backend any
individual request lands on. This is invisible to journeys — they keep calling
`.call()` and `send()` as before — and it is a no-op against a single node (the
high-water block is always present).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No module named smoke` | Running outside `make`. Use the Make targets or export `PYTHONPATH=script`. |
| `RPC_URL did not answer` | Endpoint unreachable. Check the node is up and the URL/port. |
| Everything **skipped** | Target node doesn't have the b20 features active. Activate them in the ActivationRegistry, or point `RPC_URL` at a node that has them. |
| `deployer ... underfunded ... no faucet configured` | Fund `DEPLOYER_PK`, or set `FAUCET_URL` + `FAUCET_NETWORK`. |
| Reads disagree with a write that just landed / `block not found` after ~30s | A pool backend is lagging far behind (or stuck). The provider retries for ~30s; if it still fails, the pool has a badly desynced node — check backend health. |

## Package layout

```
script/smoke/
  __main__.py         # CLI: python -m smoke <journey ...> [-k]; preflight + dispatch
  config.py           # addresses, enum/role/feature constants, env -> Config
  chain.py            # web3 harness: send/read, revert + event assertions, RPC tracing
  provider.py         # ConsistentHTTPProvider: read-your-writes over a multi-node (load-balanced) pool
  abis.py             # interface ABIs + probe/feeder artifacts, read from out/
  codec.py            # the one hand-written encode: createB20 params + initCalls
  errors.py           # selector -> custom-error-name map (from the ABIs)
  journeys/           # factory, asset_lifecycle, scheduled_multiplier, stablecoin_lifecycle, seize, policy_registry, precompile_invariants
  requirements.txt
```
