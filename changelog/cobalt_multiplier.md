# B20 Asset — Beryl → Cobalt (ERC-8056) migration

> **Audience:** teams already integrated against the B20 Asset multiplier surface on **Beryl**
> (live today). This note covers **only** the multiplier / ERC-8056 changes landing at the
> **Cobalt** hardfork.

## Summary

At Cobalt the B20 Asset multiplier surface becomes [ERC‑8056 ("Scaled UI Amount")](https://eips.ethereum.org/EIPS/eip-8056)
conformant and gains a **scheduled** multiplier setter for corporate actions. **Nothing you call
today breaks.** Every Beryl selector, event topic, and error keeps its exact 4‑byte selector /
topic0 and stays dialable at Cobalt — the deprecations below are advisory. The migration is: adopt
the canonical ERC‑8056 names (`uiMultiplier`, `toUIAmount`/`fromUIAmount`, `balanceOfUI`,
`totalSupplyUI`) and move routine multiplier changes from the instant `updateMultiplier(uint256)`
to the scheduled `updateUIMultiplier(uint256,uint256)`. **Cobalt is not live yet**; until it
activates, only the Beryl surface exists on‑chain.

## Mapping table

Selectors and topic0s below are the real values from the frozen ABIs
(`abi/v1.rs` = Beryl, `abi/v2.rs` = Cobalt); all Beryl symbols keep their selector at Cobalt.

### Functions

| Beryl symbol (selector) | Cobalt canonical (selector) | Status | Why |
| --- | --- | --- | --- |
| `multiplier()` `0x1b3ed722` | `uiMultiplier()` `0xa60bf13d` | deprecated‑name‑kept / new alias | ERC‑8056 core naming; both return the same effective multiplier. `multiplier()` stays. |
| `toScaledBalance(uint256)` `0x04f04c99` | `toUIAmount(uint256)` `0x3248d4ff` | deprecated‑dialable / new | ERC‑8056 Conversion extension; byte‑identical behavior. |
| `toRawBalance(uint256)` `0x0ca06c44` | `fromUIAmount(uint256)` `0x65cd9b3c` | deprecated‑dialable / new | ERC‑8056 Conversion extension; byte‑identical behavior. |
| `scaledBalanceOf(address)` `0x1da24f3e` | `balanceOfUI(address)` `0x437a9958` | deprecated‑name‑kept / new alias | ERC‑8056 Balances extension; alias, same value. |
| `updateMultiplier(uint256)` `0x5ffe6146` | `updateUIMultiplier(uint256,uint256)` `0x628e600f` | deprecated‑dialable / new (**not 1:1**) | Canonical path is now the **scheduled** setter; the instant setter is retained as an emergency failsafe. |
| — | `newUIMultiplier()` `0xdc767007` | new | ERC‑8056 pending‑schedule read. |
| — | `effectiveAt()` `0x97a4064f` | new | ERC‑8056 pending‑schedule read (flip timestamp). |
| — | `totalSupplyUI()` `0x9bea6429` | new | ERC‑8056 Balances extension. |
| — | `cancelUIMultiplierUpdate()` `0x2c97a0f0` | new | Cancels the single live pending update. |
| — | `MAX_UI_MULTIPLIER()` `0x785c0cf0` | new | Reads the multiplier ceiling (`type(uint128).max`) without hitting the revert path. |
| — | `supportsInterface(bytes4)` `0x01ffc9a7` | new | ERC‑165 feature detection. |

`OPERATOR_ROLE()` `0xf5b541a6`, `WAD_PRECISION()` `0x664808a8`, `announce(...)` `0x595135dd`,
`isAnnouncementIdUsed(string)` `0xc0da474e`, `batchMint(...)` `0x68573107`,
`extraMetadata(string)` `0x4ddf9da0`, and `updateExtraMetadata(string,string)` `0xb2851ef5` are
carried over unchanged.

### Events

| Beryl event (topic0) | Cobalt canonical (topic0) | Status | Why |
| --- | --- | --- | --- |
| `MultiplierUpdated(uint256)` | `UIMultiplierUpdated(uint256,uint256,uint256)` | deprecated‑still‑emitted / new | ERC‑8056 canonical event. The instant setter emits **both**; the scheduled setter emits **only** `UIMultiplierUpdated`. |
| — | `UIMultiplierUpdateCancelled(uint256,uint256)` | new | Signals a cleared pending update. |

### Errors

| Beryl error (selector) | Cobalt (selector) | Status | Why |
| --- | --- | --- | --- |
| `InvalidMultiplier()` `0x6f12f3dc` | `InvalidMultiplier()` `0x6f12f3dc` | present on Beryl already | Zero / above‑ceiling guard; now also thrown by `updateUIMultiplier`. |
| — | `EffectiveAtInPast(uint256)` `0x14119cf6` | new | `effectiveAt <= block.timestamp`. |
| — | `EffectiveAtTooFar(uint256)` `0x1ce214fa` | new | `effectiveAt > type(uint64).max`. |
| — | `UIMultiplierUpdateExists(uint256)` `0x4481a68e` | new | A live pending update already exists. |
| — | `UIMultiplierUpdateDoesNotExist()` `0xa7d6a5ca` | new | Cancel with no live pending. |

## New at Cobalt (adopt these)

### Scheduled‑update lifecycle

`updateUIMultiplier(newMultiplier, effectiveAt)` is the **canonical corporate‑action path** (stock
splits, reinvested dividends). Only **one** pending update is live at a time.

1. **Schedule** — `updateUIMultiplier(newMultiplier, effectiveAt)` (requires `OPERATOR_ROLE`,
   `effectiveAt` strictly in the future).
2. **Pending views** — while live: `newUIMultiplier()` returns the scheduled target, `effectiveAt()`
   returns the flip timestamp, and `uiMultiplier()` / `multiplier()` still return the **current**
   value.
3. **Matures lazily** — once `block.timestamp >= effectiveAt`, `uiMultiplier()` / `multiplier()`
   flip on read; **no event fires at maturation**.
4. **Or cancel** — `cancelUIMultiplierUpdate()` clears a live pending and emits
   `UIMultiplierUpdateCancelled(cancelledMultiplier, cancelledEffectiveAt)`.

To reorder overlapping actions, cancel and reschedule atomically in one announcement:
`announce([cancelUIMultiplierUpdate(), updateUIMultiplier(...)], ...)`.

### ERC‑8056 view aliases

- `uiMultiplier()` ≡ `multiplier()`
- `toUIAmount(raw)` ≡ `toScaledBalance(raw)`, `fromUIAmount(ui)` ≡ `toRawBalance(ui)`
- `balanceOfUI(account)` ≡ `scaledBalanceOf(account)`
- `totalSupplyUI()` = `totalSupply() * uiMultiplier() / WAD_PRECISION`

### Bound getter

`MAX_UI_MULTIPLIER()` returns `type(uint128).max` — the ceiling both setters enforce (the overflow
guard that keeps `balance * multiplier` inside `uint256`).

## `updateMultiplier(uint256)` retained as instantaneous admin failsafe

**Instant path is a deprecated admin failsafe** — `updateMultiplier(uint256)` sets the multiplier
  immediately and clears any live pending. It's kept for tech-debt and emergency override only, not routine use. This function can be used to instantly reverse/resolve any mistakes or developer errors made in scheduling. If used thusly it should be paired with pausing in most cases.

## Guarantees / edge cases

**Q: If a scheduled update can be cancelled, how do external consumers detect the cancellation?**
`cancelUIMultiplierUpdate()` (and the instant setter, when it supersedes a *live* pending) emits
`UIMultiplierUpdateCancelled(cancelledMultiplier, cancelledEffectiveAt)`
(topic0 `0x8838…1cad`). Watch that topic to retract a pending flip you previously staged from
`UIMultiplierUpdated`.

**Q: If the admin uses the instant failsafe, how do off‑chain indexers keep a linear, gap‑free UI‑multiplier lifecycle?**
The instant `updateMultiplier(uint256)` emits **both** the deprecated `MultiplierUpdated(uint256)`
**and** the ERC‑8056 `UIMultiplierUpdated(old, new, block.timestamp)` (and, if it clears a live
pending, `UIMultiplierUpdateCancelled` first). So every multiplier change — scheduled or emergency —
appears on the single `UIMultiplierUpdated` stream. Follow that one event and you never miss a
change; the legacy `MultiplierUpdated` topic remains available for indexers that haven't migrated.

**Q: How do I distinguish a live pending update from one that has already matured (or none)?**
A pending is **live** if `effectiveAt() > block.timestamp`. While live, `newUIMultiplier()` returns
the scheduled target (≠ `uiMultiplier()`). After maturation, `uiMultiplier()` already reflects the
new value, `newUIMultiplier() == uiMultiplier()`, and `effectiveAt()` stays at the (now past) flip
timestamp until the next schedule/instant/cancel overwrites it — so a non‑zero `effectiveAt()` that
is `<= block.timestamp` means "already applied," not "pending." When no update has ever been
scheduled, `effectiveAt() == 0`.

**Q: What if I schedule while one is already pending?**
Reverts `UIMultiplierUpdateExists(effectiveAt)` — but only a **live** pending blocks. A *matured*
(stale) pending is silently folded into the current multiplier and overwritten. To replace a live
schedule, `cancelUIMultiplierUpdate()` then `updateUIMultiplier(...)` (atomically via `announce`).

**Q: What are the `effectiveAt` bounds?**
Must be strictly in the future — `effectiveAt <= block.timestamp` reverts `EffectiveAtInPast(effectiveAt)`.
Must fit the on‑chain field — `effectiveAt > type(uint64).max` reverts `EffectiveAtTooFar(effectiveAt)`.

**Q: What are the multiplier bounds?**
`0 < newMultiplier <= MAX_UI_MULTIPLIER()` (`type(uint128).max`); zero or above reverts
`InvalidMultiplier()`. This applies to both `updateUIMultiplier` and `updateMultiplier`. Read the
ceiling from `MAX_UI_MULTIPLIER()` without risking the revert.

**Q: Do raw balances or `Transfer` semantics change?**
No. The multiplier is purely cosmetic — it rescales only the *UI/scaled* view. `balanceOf`,
`transfer`, `totalSupply`, and `Transfer` stay raw and are mechanically unaffected by any multiplier
change, scheduled or instant. Only the `*UI` / scaled reads move.
