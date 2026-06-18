# B20 Ecosystem Bug Bash — Base Sepolia

## What we're testing

We are testing **real, on-chain B20 token assets end-to-end on Base Sepolia** — both how they
**communicate with external tooling** (MetaMask and other wallets, block explorers, indexers/
APIs, DEXes) and how their **on-chain business logic** behaves (token creation, transfers,
policy enforcement, liquidity, and more).

A B20 is implemented as a Base *precompile*, not as deployed EVM bytecode. The protocol's core
logic is covered by automated tests — what those can't prove is that the *rest of the ecosystem*
treats a B20 exactly like an ordinary ERC-20, and that the user-facing business flows behave
correctly when driven through real tools. If a B20 shows as an empty account in an explorer, is
invisible to an indexer, shows the wrong decimals in MetaMask, or a policy fails to block a
restricted address, the token is broken in practice even though every low-level call "works."
This bug bash hunts those gaps by doing real on-chain actions and checking every surface.

### In scope

External tooling:

- **Wallets (MetaMask, Base App):** import by address, correct symbol/decimals/balance, send/receive, activity feed
- **Block explorers:** renders as a named precompile / ERC-20 (name, symbol, decimals, supply, holders), ABI + read/write tabs, decoded events & reverts
- **Indexers / APIs (Alchemy, CDP Coindexer):** token discovery, metadata, balances, transfer + `Memo` event streams (memo→transfer join)
- **DEX / liquidity:** approvals (incl. Permit2), provide liquidity, swaps, routing, slippage, fees, decimals normalization

Business logic:

- **Creation:** new Asset & Stablecoin via the factory (variant, decimals, currency code, deterministic `0xb20…` address)
- **Mint:** issue supply (`MINT_ROLE`) and see it reflected exactly across every surface
- **Transfers:** `transfer` / `transferFrom` / `approve`, with and without memos
- **Policy:** allow/blocklist enforcement (`PolicyForbids`), surfaced as a clean, decodable error across tools
- **Liquidity & trading:** behaves like a standard ERC-20 (pricing, decimals, fees, slippage)

### Out of scope (this round)

- Protocol internals already covered by automated tests (roles/access control, supply-cap math, EVM-context invariants)
- Burn flows + deep supply tracking across surfaces; pause & kill-switch (`ActivationRegistry`) legibility
- BerylLookup health probe + full revert/custom-error decode sweep
- Load testing + post-load state checks
- Metrics / Datadog alerting

_(Details in [Out of scope / next round](#out-of-scope--next-round).)_

### The five journeys

- **J1 — Create:** a new Asset and Stablecoin show up correctly across explorer, indexer, and wallets.
- **J2 — Mint:** minted supply is reflected exactly across wallets, explorer, and indexers/APIs.
- **J3 — Policy + transfer:** allowlist gating works and is legible; allowed transfers (incl. memos) propagate to every surface.
- **J4 — Provide liquidity:** pool init, liquidity accounting, and decimals are correct on Uniswap v4 (Base Sepolia).
- **J5 — Trade:** swaps, routing, slippage, fees, and pricing are correct and trades are legible.

---

> **Goal in one line:** a B20 is a *precompile*, not a deployed contract — but the whole
> ecosystem must treat it like a normal ERC-20. **Act on-chain, then check every off-chain
> surface (explorer, indexer/APIs, wallet, DEX). Log anything that looks off.**

This bug bash is a **human-driven, end-to-end pass on Base Sepolia** — we do real on-chain
actions through real tools and confirm both the ecosystem integration and the business logic hold up.

**Scope:** Base Sepolia · ecosystem happy-path (journeys **J1–J5**) · surfaces = explorer +
indexers/APIs + wallets + DEX/liquidity. Deeper protocol/failure-mode coverage is listed in
[Out of scope / next round](#out-of-scope--next-round).

**Time-box:** ~2 hours. Setup (15 min) → journeys (≈90 min) → triage findings (15 min).

---

## 0. Precompile addresses (source of truth)

Always read addresses from [`src/StdPrecompiles.sol`](../src/StdPrecompiles.sol). Do **not**
trust addresses copied from slides/docs — an earlier PRD draft used `0xB20…000F` for the
factory, which is **not** the shipped value. As of this writing:

| Precompile | Address |
|---|---|
| `B20Factory` | `0xB20f000000000000000000000000000000000000` |
| `PolicyRegistry` | `0x8453000000000000000000000000000000000002` |
| `ActivationRegistry` | `0x8453000000000000000000000000000000000001` |

Deployed B20 tokens are derived deterministically and start with the `0xb20…` prefix — that
prefix is the detection mechanism explorers/indexers use to special-case them.

> If the table above ever disagrees with `src/StdPrecompiles.sol`, **the source file wins** —
> update this doc and flag it in the bug-bash channel.

---

## 1. Setup (do this before the bash starts)

### 1.1 Confirm Beryl + features are active on Sepolia

B20 only works once the **Beryl** hardfork is active **and** the B20 features are switched on
in the `ActivationRegistry`. Beryl activates on Sepolia **Thu Jun 18 2026, 14:00 ET** — do
not start before then.

- Quick check: try creating a token ([J1](#j1--create-a-b20--does-the-ecosystem-see-it)). If
  creation reverts with a feature-not-activated error (or the factory address has no code),
  the chain isn't ready yet.
- On **Sepolia**, feature activation lands via the activate-features PR (not the playground).
  The playground activation flow in the B20 doc's *Launch Checklist* applies to vibenet/zeronet.

### 1.2 Wallets & funds

- Create two EOAs: `cast wallet new` (twice). One is the deployer/admin, one is a second actor.
- Fund both from the faucet: **https://base-faucet-dev.cbhq.net/**
- Add **Base Sepolia** to both **MetaMask** and the **Base App** (for the wallet surface).

### 1.3 Participant roster

Assign each person a surface so coverage isn't duplicated. Everyone runs the same actions;
each owns verifying their surface.

| Participant | Surface | Tooling |
|---|---|---|
|  | Explorer | Sepolia block explorer (token + tx pages, ABI/read-write tabs) |
|  | Indexer / APIs | Alchemy (`getTokenBalances`, token metadata), CDP Coindexer |
|  | Wallet | Base App + MetaMask (import, balance, send, activity) |
|  | DEX / liquidity | Uniswap v4 on Base Sepolia (PoolManager + test routers), Permit2 |

---

## 2. Journeys (the core — J1–J5)

For each journey: follow the numbered steps in the **playground** (https://protocols-native-token-playground.pages.coinbase.ghe.com/), then tick the **per-surface** checks. Anything unchecked or surprising → [log it](#3-bug-logging-template).

> Tip: share the created token address in the channel so everyone is looking at the same token.

### J1 — Create a B20 → does the ecosystem see it?

Create one **Asset** and one **Stablecoin** via the playground, then confirm every surface sees the token correctly.

#### Step 1 — Connect

1. Open the playground and go to the **connect** tab.
2. Under **Network**, select **Base Sepolia** and connect with your wallet.

#### Step 2 — Predict the address before creating

1. Go to the **utils** tab.
2. Select the variant you're about to create (**ASSET** or **STABLECOIN**).
3. Enter your wallet address as the sender and click **random** to generate a salt. Copy the salt.
4. Click **predict address →**. Copy the predicted address — the deployed token must match it exactly.
- [ ] Predicted address shown, starts with `0xb20…`.

#### Step 3 — Create an Asset token

1. Go to the **tokens** tab. Click **▾ Create Token**.
2. Select variant **ASSET**.
3. Fill in **name** (e.g. `Test Asset`), **symbol** (e.g. `TAST`), and **decimals** (e.g. `18`).
4. Set **initialAdmin** to your wallet address.
5. Paste the salt from Step 2 into the salt field.
6. Click **predict address** to confirm it matches Step 2, then click **createB20(ASSET) →**.
7. Confirm the transaction. The token appears in **Recently created tokens** with its address.
- [ ] Deployed address matches the predicted address from Step 2.
- [ ] Address starts with `0xb20`.

#### Step 4 — Create a Stablecoin token

1. Repeat Step 3 with variant **STABLECOIN**, a new name/symbol, and a **currency code** (e.g. `USD`). Decimals are fixed at 6.
- [ ] Stablecoin created, address shown.

#### Step 5 — Check every surface

Share both token addresses in the channel so every participant checks the same tokens.

- [ ] **Explorer:** open each token address on the Sepolia block explorer. It renders as a named ERC-20 (name, symbol, decimals, supply visible). ABI tab and read/write tabs are present — not an empty account page.
- [ ] **Indexer / API:** Alchemy `getTokenMetadata` and `getTokenBalances` return the token. CDP Coindexer knows the token. Symbol and decimals match what was set at creation.
- [ ] **Wallet:** import each token by address in **MetaMask** and **Base App** → correct symbol, decimals, and zero balance shown.

**Expected:** A freshly created B20 is indistinguishable from a normal ERC-20 to every surface.

### J2 — Mint supply → does it show up everywhere?

Mint B20 supply to yourself and a second wallet, then confirm the new balances are reflected across every surface.

#### Step 1 — Grant MINT_ROLE to yourself

1. In the **tokens** tab, click your Asset token from the list (or load it by address).
2. Go to the **Authz** section.
3. Find **MINT_ROLE** in the role list. If the **grant to self** button is shown, click it and confirm.
- [ ] MINT_ROLE shows ✓ held after granting.

#### Step 2 — Mint to yourself

1. Go to the **Supply** section of the token.
2. In the **mint(to, amount)** row, enter your wallet address as `to` and an amount (e.g. `1000000000` for 1 token at 9 decimals — adjust for your token's decimals).
3. Click **send** and confirm.
- [ ] Tx confirms. `totalSupply` increases by exactly the minted amount — check via the **Ledger** section or the explorer.

#### Step 3 — Mint to a second wallet

1. Still in **Supply**, change `to` to the second wallet address.
2. Mint a different amount (e.g. `500000000`).
3. Click **send** and confirm.
- [ ] Second wallet's balance shows in the **Ledger** section (`balanceOf`).

#### Step 4 — Attempt unauthorized mint

1. Switch to the second wallet (change private key in the connect tab).
2. Load the same token. Go to **Supply** and try to mint.
3. The tx should revert — the second wallet has no `MINT_ROLE`.
- [ ] Tx reverts with a decodable error (shown in the playground result panel, not an opaque hex blob).
- [ ] Total supply is unchanged.

#### Step 5 — Check every surface

- [ ] **Explorer:** token page shows updated `totalSupply` and both holders listed.
- [ ] **Wallet:** both wallets show the correct balance with correct decimals in **MetaMask** and **Base App**.
- [ ] **Indexer / API:** Alchemy `getTokenBalances` returns the correct balance for each address. CDP Coindexer reflects the new supply.

**Expected:** Minted supply is reflected exactly and consistently across wallets, explorer, and indexers.

### J3 — Attach a policy & transfer → does gating work and propagate?

Create an allowlist policy, attach it to the token, confirm allowed transfers go through and blocked ones fail cleanly.

#### Step 1 — Create an allowlist policy

1. Go to the **registry** tab.
2. Under **Create Policy**, select **ALLOWLIST**.
3. Set **admin** to your wallet address.
4. In **initial accounts**, paste wallet A's address (the one that will be allowed to receive).
5. Click **createPolicy →** and confirm.
6. Note the **policy id** shown in the result (e.g. `2`).
- [ ] Policy created. Policy id shown.

#### Step 2 — Attach the policy to the token

1. Go to the **tokens** tab, load your B20 token.
2. Go to the **Compliance** section.
3. From the **policy slot** dropdown, select **TRANSFER_RECEIVER_POLICY**.
4. Enter the policy id from Step 1 in the **policy id** field.
5. Click **send** and confirm.
- [ ] `updatePolicy` tx confirms. The policy slot now shows the new policy id.

#### Step 3 — Transfer to the allowlisted wallet (should succeed)

1. Go to the **Ledger** section.
2. In the **transfer(to, amount)** row, enter wallet A's address and an amount.
3. Click **send** and confirm.
- [ ] Transfer succeeds, tx hash returned.
- [ ] Wallet A's balance updated in the **Ledger** section (`balanceOf`).
- [ ] **Explorer:** tx shows a decoded `Transfer` event with correct addresses and amount.

#### Step 4 — Transfer with a memo

1. Still in **Memo** section (or the memo transfer row in Ledger), send a transfer to wallet A with a memo value.
2. Confirm the tx.
- [ ] Tx confirms. Explorer shows both a `Transfer` event and a `Memo` event in the same tx — `Memo` log index is immediately after `Transfer`.

#### Step 5 — Transfer to a non-member (should fail)

1. In the **Ledger** section, enter a wallet address that is **not** in the allowlist.
2. Click **send**.
- [ ] Tx reverts. The playground shows `PolicyForbids` (not an opaque hex error).
- [ ] No balance change on either address.
- [ ] **Explorer:** the failed tx shows the decoded `PolicyForbids` custom error.
- [ ] **Wallet:** wallet / MetaMask surfaces the error legibly (not "execution reverted").

#### Step 6 — Check propagation

- [ ] Sender and wallet A balances updated correctly in **MetaMask** and **Base App** after the allowed transfer.
- [ ] Indexer / API reflects the new balance for wallet A.
- [ ] Activity feed in the wallet shows the transfer.

> Note: RPCs are load-balanced — if an API shows a stale balance immediately after a confirmed write, note the backend name and how long it took to catch up.

**Expected:** Policy gating works and is legible everywhere; allowed transfers propagate to every surface.

### J4 — Provide liquidity (Uniswap v4, Base Sepolia)

Stand up a real market for the B20 on Uniswap v4 and confirm liquidity accounting is correct.
Use the **Uniswap tab** in the playground (https://protocols-native-token-playground.pages.coinbase.ghe.com/).

#### Step 1 — Connect to Base Sepolia

1. Open the playground and go to the **connect** tab.
2. Under **Network**, select **Base Sepolia** — the RPC fills in automatically.
3. Connect with your wallet (browser wallet or private key).
4. The app switches to the **uniswap** tab automatically.
5. Make sure you have B20 tokens in your wallet before continuing — go to the **tokens** tab, load your B20, and mint some to yourself via the Supply section if needed.

#### Step 2 — Define the Pool Key

The Pool Key identifies the pool. Every action below uses the same key.

1. In the **Pool Key** card at the top of the Uniswap tab, fill in:
   - **currency0** — click **ETH** to fill the native ETH sentinel address (`0xEeee…EE`). ETH must always be currency0.
   - **currency1** — paste your B20 token address.
   - **fee** — select **0.3% (3000)** from the dropdown. Tick spacing fills in as **60** automatically.
   - **hooks** — click **none** to fill the zero address.
2. Check that the **Pool ID** (`bytes32`) appears below the fields. Copy it and share it with the team so everyone is targeting the same pool.
- [ ] Pool ID is shown and non-zero.

#### Step 3 — Read pool state (is the pool initialized?)

1. In the **Pool State** card, click **read pool state**.
2. The result shows `sqrtPriceX96`, `tick`, and `liquidity` from `StateView`.
   - If `sqrtPriceX96 = 0` → pool not yet initialized. Continue to Step 4.
   - If `sqrtPriceX96 > 0` → pool already exists. Skip to Step 5.
- [ ] Pool State read succeeds (no RPC error).

#### Step 4 — Initialize the pool

1. In the **Initialize Pool** card, click the **1:1** preset button. This fills `sqrtPriceX96 = 79228162514264337593543950336` (a 1:1 starting price).
2. Click **initialize →**. Confirm the transaction in your wallet.
3. After the tx confirms, go back to **Pool State** and click **read pool state** again.
- [ ] `sqrtPriceX96` is now non-zero and matches the value you set.
- [ ] `tick` is 0 (or near 0 for a 1:1 price).
- [ ] Attempting to initialize the same pool key again reverts with `AlreadyInitialized`.

#### Step 5 — Add liquidity

1. In the **Manage Liquidity** card, set:
   - **tick lower** — `-887220` (full range for tickSpacing 60)
   - **tick upper** — `887220`
   - **liquidity delta** — `1000000000000000000` (1e18 liquidity units; adjust up if the tx reverts with insufficient amounts)
   - **msg.value** — the ETH amount to deposit in wei (e.g. `100000000000000000` for 0.1 ETH). Required because currency0 is native ETH.
2. Click **add liquidity →**. Confirm the transaction.
3. After the tx confirms, click **read pool state** — `liquidity` should now be non-zero.
4. In the **read position info** row, confirm your address is in the field and click **read** — your position's liquidity should match what you added.
- [ ] `StateView.getLiquidity` is non-zero after adding.
- [ ] `getPositionInfo` shows non-zero liquidity for your position.
- [ ] PoolManager's B20 balance increased (check on the explorer — the PoolManager address custodies all funds).

Also add a **narrow in-range** position (e.g. tick lower `-600`, tick upper `600`) and an **out-of-range** position (e.g. tick lower `600`, tick upper `1200` — both above current tick). The out-of-range position deposits single-sided (B20 only, no ETH).

- [ ] Out-of-range position deposits only one token (no ETH taken).
- [ ] `StateView.getLiquidity` reflects only the in-range liquidity (out-of-range positions don't count).

#### Step 6 — Check decimals normalization

Do this for both a **6-decimal** and an **18-decimal** B20.

1. After initializing with a 1:1 `sqrtPriceX96`, click **read pool state** and note `sqrtPriceX96`.
2. In the **Quote** card (Step 7 below), request a quote for a round number (e.g. 1000000 = 1 USDC if 6-dec). Confirm the output is a sane amount — not 1e12× off.
- [ ] Quote output is a reasonable amount for both 6-dec and 18-dec tokens.
- [ ] No `1e±12` price discrepancy that would signal a wrong `decimals()` read.

#### Step 7 — Remove liquidity

1. In the **Manage Liquidity** card, use the same tick range you added with (`-887220` / `887220`).
2. Enter the same liquidity delta you added.
3. Click **remove liquidity →**. Confirm the transaction.
4. Click **read pool state** — `liquidity` should return to 0 (or whatever remained from other positions).
5. Click **read position info** — your position's liquidity should be 0.
- [ ] Tokens credited back to your wallet after removal.
- [ ] `StateView.getLiquidity` returns to baseline.
- [ ] Position liquidity is 0.

**Expected:** A B20 anchors a real v4 pool exactly like a standard ERC-20 — initialize, add/remove liquidity, concentrated positions, decimals, and fee accrual all correct.

---

### J5 — Trading / swaps (Uniswap v4, Base Sepolia)

With the pool live from J4, run swaps through the playground's Uniswap tab. Keep the same **Pool Key** from J4.

#### Step 1 — Get a quote before swapping

1. In the **Quote** card, select direction: **token0 → token1** (ETH → B20).
2. Enter an input amount (e.g. `1000000000000000` for 0.001 ETH in wei).
3. Click **get quote →**. No transaction is sent — this is read-only.
4. Note the `deltaAmount0` (ETH in) and `deltaAmount1` (B20 out) shown in the result.
- [ ] Quote returns without error.
- [ ] Output amount is a sane number (not 0, not 1e24).

#### Step 2 — Swap ETH → B20

1. In the **Swap** card, select **token0 → token1**.
2. Enter the same amount you quoted (e.g. `1000000000000000`).
3. Leave **use max price limit** checked — this prevents the swap from reverting on slippage.
4. Click **swap →**. Confirm the transaction.
5. After the tx confirms, click **read pool state** — `sqrtPriceX96` and `tick` should have moved.
- [ ] Swap succeeds, tx hash returned.
- [ ] `sqrtPriceX96` changed (price moved in the expected direction).
- [ ] Your B20 balance increased by approximately the quoted `deltaAmount1`.
- [ ] Your ETH balance decreased by approximately the input amount.

#### Step 3 — Swap B20 → ETH (reverse direction)

1. In the **Swap** card, select **token1 → token0**.
2. If the **approve [token]** button appears (the playground checks your B20 allowance for PoolSwapTest automatically), click it first and confirm the approval transaction.
3. Enter an input amount in B20 units.
4. Click **swap →**. Confirm.
- [ ] Approval tx succeeds (if needed).
- [ ] Swap succeeds.
- [ ] Price moves in the opposite direction from Step 2.

#### Step 4 — Quote matches execution

1. Note the `deltaAmount1` from a Quote call.
2. Run the swap with the same inputs.
3. Compare the actual output in your wallet to the quoted amount.
- [ ] Actual output is within a small margin of the quoted amount (no silent drift — large discrepancy signals the pool is misreading B20 decimals or balances).

#### Step 5 — Verify accounting

1. Check the B20's `totalSupply` via the **tokens** tab → **Ledger** section.
2. Run several more swaps in both directions.
3. Check `totalSupply` again.
- [ ] `totalSupply` is unchanged after swaps (swaps move balances, never mint or burn).
- [ ] Pool state (`sqrtPriceX96`, `tick`, `liquidity`) updates after each swap.

#### Step 6 — Check fee accrual

After running swaps in Step 2–4, the in-range position from J4 should have accrued fees.

1. In the **Manage Liquidity** card, click **read position info** for your full-range position.
2. Check `feeGrowthInside0LastX128` and `feeGrowthInside1LastX128` — both should be non-zero.
3. Remove liquidity (same as J4 Step 7) — the tokens returned should be slightly more than you put in.
- [ ] Fee growth fields are non-zero after swaps crossed the position.
- [ ] Removing liquidity returns more tokens than deposited.

#### Step 7 — Verify on-chain surfaces

For each swap tx, check:
- [ ] **Explorer:** tx shows decoded `Transfer` events for the B20; the PoolManager page shows a `Swap` event.
- [ ] **Indexer / analytics:** trades appear in event streams; pool price and TVL update.

**Expected:** Swaps, quoting, slippage, and pricing behave as for a standard ERC-20, and trades are legible to explorers and indexers.

---

## 3. Bug logging template

Copy this block per finding into the [findings log](#4-findings-log) and/or the tracker:

```
Surface:   explorer | indexer/api | wallet | dex
Journey:   J1 | J2 | J3 | J4 | J5
Token:     0xb20...            Network: Base Sepolia
Steps:     <exact steps to reproduce>
Expected:  <what a normal ERC-20 would do>
Actual:    <what happened>
Severity:  P0 (launch-blocking) | P1 | P2
Owner:     <triage owner>
Repro tx:  <tx hash / API request>
```

---

## 4. Findings log

| # | Surface | Journey | Severity | Summary | Repro (tx/req) | Owner | Status |
|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |

---

## Out of scope / next round

Called out so these gaps aren't mistaken for "covered":

- **Burn & deep supply tracking:** burn flows, plus explorer holder-ratio and indexer supply
  tracking mint/burn exactly across surfaces.
- **Pause & kill-switch legibility:** paused transfers and `ActivationRegistry` deactivation
  surface clean errors to wallets/DEXes while reads keep serving explorers/indexers.
- **Failure-mode legibility:** BerylLookup health probe (a known B20 actually responds —
  otherwise *silent* total failure), and a full revert/custom-error decode sweep across surfaces.
- **Load testing:** run load tests, then re-verify state is intact under throughput.
- **Metrics:** confirm Datadog alerts fire.

See [`docs/b20-launch-risk-assessment.md`](./b20-launch-risk-assessment.md) and the B20 doc's
*Smoke Testing Suite* tab for the deeper invariant list.

---

## Reference links

- Component docs: [`docs/B20`](./B20/README.md) · [`docs/PolicyRegistry`](./PolicyRegistry/README.md) · [`docs/ActivationRegistry`](./ActivationRegistry/README.md)
- Risk assessment: [`docs/b20-launch-risk-assessment.md`](./b20-launch-risk-assessment.md)
- Faucet: https://base-faucet-dev.cbhq.net/
- Playground (B20 + Uniswap V4): https://protocols-native-token-playground.pages.coinbase.ghe.com/ — switch to **Base Sepolia** in the Connect tab to access the Uniswap tab (J4/J5)
- B20 design doc: *B20 (Base Native ERC20)* Google doc — PRD, Launch Checklist, Risks + Mitigations, Explorer Requirements tabs.
