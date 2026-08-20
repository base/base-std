# Schedule Multiplier Updates (ERC-8056)

- **Feature Name**: Scheduled Multiplier
- **Start Date**: 2026-08-17
- **Authors**: Markus
- **Title**: Schedule Multiplier Updates (ERC-8056)

## Summary

This change introduces a scheduled multiplier setter for B20 Asset issuers running corporate actions. The multiplier setter moves from an instant path to a scheduled path aligned with ERC-8056. The change applies only to B20 Asset in the Cobalt hardfork.

Two audiences are affected. Issuers and operators own the write path and use `updateUIMultiplier` to schedule a multiplier change, `cancelUIMultiplierUpdate` to clear a pending update, and the retained `updateMultiplier` instant setter as an emergency failsafe. All three write functions require `OPERATOR_ROLE`. Integrators, indexers, and custodians own the read and event path. They read the pending schedule through `newUIMultiplier()` and `effectiveAt()`, prefer the new `UIMultiplierUpdated` event over the deprecated `MultiplierUpdated` event, and handle lazy maturation of the multiplier flip.

The scheduled setter enables two corporate action use cases: stock splits (both forward and reverse) and in-kind dividends. Forward splits and reinvested dividends are value-neutral to raw venues and do not require an on-chain halt. Reverse splits are not value-neutral. Operators should pause `PausableFeature.TRANSFER` across the flip window for reverse splits, and should similarly bracket any instant `updateMultiplier` call used for a reverse-adjacent change. The legacy `updateMultiplier` instant setter is retained as an emergency failsafe to correct a wrong scheduled value.

## Motivation

Before this change, B20 Asset did not have a scheduled setter. Multiplier changes used only the instant `updateMultiplier` path. Corporate actions such as stock splits and in-kind dividends require advance notice. Exchanges, custodians, and off-chain accounting systems must prepare before the multiplier flips. An instant setter forces every downstream system to react at write time, which is not operable at issuer scale. A scheduled setter lets issuers commit to a target multiplier and a future effective timestamp on-chain. Downstream systems can read the pending update and prepare before it takes effect. This change conforms to ERC-8056, which defines a standard for scheduling changes to a real-world asset token.

## Background

ERC-8056 (https://eips.ethereum.org/EIPS/eip-8056) defines a standard for scheduling changes to a real-world asset token. B20 Asset is an RWA token standard that conforms to the ERC-20 specification. Prior to this change, B20 Asset provided these functions:

- `updateMultiplier(uint256 newMultiplier)`: applies the multiplier immediately
- `toScaledBalance(uint256)` and `toRawBalance(uint256)`: legacy read and conversion aliases that predate the ERC-8056 naming

## Specs

### Interface Changes

The following tables describe new, renamed, and deprecated symbols. Selector and topic0 values are verified against the implementation.

#### Functions

| Symbol | Selector | Status | Notes |
| --- | --- | --- | --- |
| `updateUIMultiplier(uint256,uint256)` | `0x628e600f` | new | Canonical scheduled setter for corporate actions. |
| `cancelUIMultiplierUpdate()` | `0x2c97a0f0` | new | Cancels the single live pending update. |
| `newUIMultiplier()` | `0xdc767007` | new | ERC-8056 pending-schedule read (target multiplier). |
| `effectiveAt()` | `0x97a4064f` | new | ERC-8056 pending-schedule read (flip timestamp). |
| `totalSupplyUI()` | `0x9bea6429` | new | ERC-8056 Balances extension. |
| `MAX_UI_MULTIPLIER()` | `0x785c0cf0` | new | Reads the multiplier ceiling (`type(uint128).max`), letting callers validate a proposed multiplier before scheduling without triggering the `InvalidMultiplier` revert path. |
| `supportsInterface(bytes4)` | `0x01ffc9a7` | new | ERC-165 feature detection. |
| `uiMultiplier()` | `0xa60bf13d` | new alias | ERC-8056 core naming. Aliases `multiplier()`; returns the same effective value. |
| `balanceOfUI(address)` | `0x437a9958` | new alias | ERC-8056 Balances extension. Aliases `scaledBalanceOf(address)`; returns the same value. |
| `toUIAmount(uint256)` | `0x3248d4ff` | new | ERC-8056 Conversion extension. Byte-identical to `toScaledBalance`. |
| `fromUIAmount(uint256)` | `0x65cd9b3c` | new | ERC-8056 Conversion extension. Byte-identical to `toRawBalance`. |
| `multiplier()` | `0x1b3ed722` | unchanged (canonical name) | Canonical B20 name; `uiMultiplier()` is the ERC-8056 alias. |
| `scaledBalanceOf(address)` | `0x1da24f3e` | unchanged (canonical name) | Canonical B20 name; `balanceOfUI(address)` is the ERC-8056 alias. |
| `toScaledBalance(uint256)` | `0x04f04c99` | deprecated-dialable | Prefer `toUIAmount(uint256)`. Byte-identical behavior. |
| `toRawBalance(uint256)` | `0x0ca06c44` | deprecated-dialable | Prefer `fromUIAmount(uint256)`. Byte-identical behavior. |
| `updateMultiplier(uint256)` | `0x5ffe6146` | deprecated-dialable | Retained as emergency failsafe. Instant setter; clears any live pending update. Prefer scheduled `updateUIMultiplier`. |

#### Events

| Symbol | Topic0 | Status | Notes |
| --- | --- | --- | --- |
| `UIMultiplierUpdated(uint256,uint256,uint256)` | `0x2205df4534432b2f60654a3fdb48737ffdaf3e9edb1a498bd985bc026b15b055` | new | ERC-8056 canonical multiplier-change event. Parameters are `(oldMultiplier, newMultiplier, effectiveAtTimestamp)`. Emitted by both setters; the instant setter stamps `effectiveAtTimestamp = block.timestamp`. |
| `UIMultiplierUpdateCancelled(uint256,uint256)` | `0x883856335ba5f60c18b9817c4505d3c7d3f6223dcf39516b30c508c46a5e1cad` | new | Signals a cleared pending update (via cancel or a superseding instant setter). |
| `MultiplierUpdated(uint256)` | `0x4dbe4840d7465bd162f67814cea0b519567a2e0e578bcde61e7f4ced361e5a3d` | deprecated-still-emitted | Legacy event. Emitted only by the instant setter (`updateMultiplier`) alongside `UIMultiplierUpdated`. The scheduled setter emits only `UIMultiplierUpdated`. |

#### Errors

| Symbol | Selector | Status | Notes |
| --- | --- | --- | --- |
| `EffectiveAtInPast(uint256)` | `0x14119cf6` | new | Thrown when `effectiveAt <= block.timestamp`. |
| `EffectiveAtTooFar(uint256)` | `0x1ce214fa` | new | Thrown when `effectiveAt > type(uint64).max`. |
| `UIMultiplierUpdateExists(uint256)` | `0x4481a68e` | new | Thrown when a live pending update already exists. |
| `UIMultiplierUpdateDoesNotExist()` | `0xa7d6a5ca` | new | Thrown when cancel is called with no live pending update. |
| `InvalidMultiplier()` | `0x6f12f3dc` | unchanged | Error symbol and selector unchanged. Zero or above-ceiling guard. Now also thrown by `updateUIMultiplier`, and newly thrown by `updateMultiplier` for `newMultiplier > type(uint128).max`. Pre-Cobalt `updateMultiplier` rejected only zero. See Compatibility behavior under Behavioural Changes. |

#### Interface IDs advertised via `supportsInterface`

| Interface ID | Interface | Status |
| --- | --- | --- |
| `0x01ffc9a7` | `IERC165` | new advertisement |
| `0xa60bf13d` | `IScaledUIAmount` (ERC-8056 core) | new advertisement |
| `0x4bd27648` | `IScaledUIAmountNewUIMultiplier` (ERC-8056 pending) | new advertisement |
| `0xd890fd71` | `IScaledUIAmountBalances` (ERC-8056 optional) | new advertisement |
| `0x57854fc3` | `IScaledUIAmountConversion` (ERC-8056 optional) | new advertisement |

ERC-8056 conformance note: The optional `TransferWithUIAmount` event is intentionally not implemented. Scaled balances are derivable from the raw `Transfer` log and the active multiplier, so the event is redundant (see `docs/B20/Asset.md`).

### Behavioural Changes

#### Old Behavior

The `updateMultiplier(uint256)` function applied the multiplier immediately. The change emitted the deprecated `MultiplierUpdated(uint256)` event.

#### New Behavior

The `updateUIMultiplier(uint256 newMultiplier, uint256 effectiveAt)` function is the canonical path for routine corporate actions. The caller schedules one pending multiplier update for a future timestamp. The pending update becomes effective lazily on read when `block.timestamp >= effectiveAt`. No extra event fires at maturation time. Off-chain systems must read `uiMultiplier()` or watch the pending schedule. The `newUIMultiplier()` and `effectiveAt()` functions expose the live pending update. The `cancelUIMultiplierUpdate()` function clears the live pending update and emits `UIMultiplierUpdateCancelled(uint256,uint256)`.

#### Live Pending Definition

A pending update is **live** while `effectiveAt > block.timestamp` and **matured** once `effectiveAt <= block.timestamp`. The `updateUIMultiplier` function reverts with `UIMultiplierUpdateExists` only against a **live** pending update. A matured pending update does **not** block a new schedule; it is folded first (see Maturation). The `cancelUIMultiplierUpdate` function reverts with `UIMultiplierUpdateDoesNotExist` when there is no live pending update, including when the only pending update has already matured.

#### Maturation and Materialization

After `effectiveAt`, reads **compute** the flipped value on the fly. Storage slot 1 (current multiplier) is **not** written at maturation. The matured value is "folded" into slot 1 only on the **next** `updateUIMultiplier`, `updateMultiplier`, or `cancelUIMultiplierUpdate` call. This fold emits **no** event.

While matured-but-unfolded: `newUIMultiplier()` mirrors `uiMultiplier()` (both return the matured value, **not** 0), and `effectiveAt()` retains its now-past timestamp (**not** reset to 0) until the next setter folds it.

Integration guidance: Detect a live pending update via `effectiveAt() > block.timestamp`. Never test `effectiveAt() == 0`.

#### Compatibility Behavior

The `updateMultiplier(uint256)` function remains callable as a deprecated instant failsafe. It newly reverts with `InvalidMultiplier` for `newMultiplier > type(uint128).max`. Pre-Cobalt it rejected only zero; the ceiling is added in this change so `balance * multiplier` stays within `uint256` (matching the scheduled setter). The bound (~`3.4e20`× as a WAD multiplier) is unreachable for realistic corporate actions. This is a precise-guarantee note, not a practical breaking change.

The instant setter applies the multiplier immediately and clears any pending update. If it clears a **live** pending update, it emits `UIMultiplierUpdateCancelled(...)` first, then emits the legacy `MultiplierUpdated(uint256)` event and the canonical `UIMultiplierUpdated(uint256,uint256,uint256)` event. If it clears a **matured** pending update, it folds the matured value silently (**no** `UIMultiplierUpdateCancelled`), then emits `MultiplierUpdated(uint256)` and `UIMultiplierUpdated(uint256,uint256,uint256)`.

#### Access Control

All three write functions — `updateUIMultiplier`, `cancelUIMultiplierUpdate`, and `updateMultiplier` — require `OPERATOR_ROLE`. This role is pre-existing (not introduced by this change) and already gates `announce`.

#### Pause Interaction

No new `PausableFeature` is added. The `updateUIMultiplier`, `cancelUIMultiplierUpdate`, and `updateMultiplier` functions are not subject to any pause vector. For a reverse split (not value-neutral — see Summary), operators should manually pause `TRANSFER` across the flip window (see `docs/B20/Asset.md`). The instant `updateMultiplier` bypasses the scheduling window entirely, so a reverse-adjacent instant change should likewise be pause-bracketed.

#### Gas Cost Implications

Every scaled-view read (`uiMultiplier`, `multiplier`, `balanceOfUI`, `scaledBalanceOf`, `toUIAmount`, `fromUIAmount`, `totalSupplyUI`) now includes an extra `SLOAD` for the pending slot plus a `block.timestamp` compare. Raw `balanceOf` is unchanged.

#### Storage Layout Changes

A new field `PendingMultiplier pending` is appended to the `base.b20.asset` ERC-7201 namespace.

- Namespace location: `0xfdc6d4552d1286ade4d9facdbf0fb50d2ec9b89a90e104f26fd277585e374b00`
- Placed at `PENDING_OFFSET = 4`

The field is packed into a single 256-bit slot:

- Bits 0-127: `uint128 multiplier` (target)
- Bits 128-191: `uint64 effectiveAt` (flip timestamp)
- Bits 192-255: unused (32 bytes free for future packing)

This is an additive change. Pre-existing offsets 0-3 are unchanged:

- Offset 0: `uint8 decimals`
- Offset 1: `uint256 multiplier` (stored `0` still interpreted as `WAD_PRECISION` on read)
- Offset 2: `mapping usedAnnouncementIds`
- Offset 3: `mapping extraMetadata`

The layout must match the `base/base` Rust precompile slot-for-slot (AGENTS.md invariant).

#### ERC-8056 View Aliases

Alias mappings (`uiMultiplier`↔`multiplier`, `balanceOfUI`↔`scaledBalanceOf`, `toUIAmount`↔`toScaledBalance`, `fromUIAmount`↔`toRawBalance`) are listed in the Functions table. Each returns the same value as its canonical counterpart. The `totalSupplyUI()` function equals `totalSupply() * uiMultiplier() / WAD_PRECISION`.

#### Edge Cases and Precision

Raw balances are **canonical** and are never rewritten by a multiplier flip. A flip only changes the derived scaled/UI view.

Scaled views are computed as `raw * multiplier / WAD_PRECISION`, floored (integer division). The `fromUIAmount` / `toRawBalance` functions are also floored, so the round-trip is lossy by up to one unit (1 ULP) when `multiplier != WAD_PRECISION`.

A deep **reverse split** can make floored dust economically visible at low decimals. Prefer 18 decimals for equities so it stays noise (see `docs/B20/Asset.md`).

Scheduling boundary: `effectiveAt` must be strictly in the future (`effectiveAt <= block.timestamp` reverts `EffectiveAtInPast`); maturation triggers at `block.timestamp >= effectiveAt`. There is no overlap — a schedule cannot target "now," and the pending flips the instant its timestamp is reached.

### Examples

The `updateUIMultiplier(newMultiplier, effectiveAt)` function is the canonical path for corporate actions such as stock splits and reinvested dividends. Only one pending update can be live at a time.

1. **Schedule**: Call `updateUIMultiplier(newMultiplier, effectiveAt)`. This requires `OPERATOR_ROLE`, and `effectiveAt` must be strictly in the future.
2. **Read the pending update**: While it is live, `newUIMultiplier()` returns the scheduled target, `effectiveAt()` returns the flip timestamp, and `uiMultiplier()` / `multiplier()` still return the current value.
3. **Let it mature**: Once `block.timestamp >= effectiveAt`, `uiMultiplier()` / `multiplier()` flip on read. No event fires at maturation.
4. **Or cancel it**: `cancelUIMultiplierUpdate()` clears a live pending update and emits `UIMultiplierUpdateCancelled(cancelledMultiplier, cancelledEffectiveAt)`.

To reorder overlapping actions, cancel and reschedule atomically in one announcement: `announce([cancelUIMultiplierUpdate(), updateUIMultiplier(...)], ...)`.

## Design Decisions & Alternatives Considered

The instant setter (`updateMultiplier`) is retained as a deprecated dialable failsafe. It is the only on-chain recourse to correct or supersede a scheduled multiplier without waiting for `effectiveAt`. A cancel-then-schedule sequence cannot fix a bad scheduled value if the correction must apply immediately. Removing the instant setter would leave operators with no emergency override if a wrong `newMultiplier` or wrong `effectiveAt` were scheduled. It is gated by the pre-existing `OPERATOR_ROLE` (same as scheduling), not a narrower emergency-only role.

A single pending slot (one live update at a time) is used instead of a queue. This choice was made for simplicity, gas efficiency, and single-slot storage packing. Reordering overlapping actions is handled by an atomic cancel-then-schedule in one announcement (see Examples).

## Migration Steps

Old functions work; there are no breaking changes. Migration steps are to update the workflow to use what is shown in the Examples section.

Deprecation lifecycle (two tiers):

- `updateMultiplier` is retained **indefinitely** as the emergency failsafe. It is not scheduled for removal — it is the only immediate on-chain override for a mis-scheduled value or timestamp.
- `toScaledBalance`, `toRawBalance`, and the legacy `MultiplierUpdated` event are deprecated-dialable for backward compatibility, with **no removal committed**. A future hardfork may remove them; none is scheduled.

Off-chain integrators: Detect a live pending update via `effectiveAt() > block.timestamp`, never `== 0` (see Maturation and Materialization under Behavioural Changes). Prefer listening for `UIMultiplierUpdated` over the deprecated `MultiplierUpdated`.