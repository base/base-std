# Schedule Multiplier Updates (ERC-8056)

- **Feature Name**: Scheduled Multiplier
- **Start Date**: 2026-08-17
- **Authors**: Markus
- **Title**: Schedule Multiplier Updates (ERC-8056)

## Summary

This change introduces a scheduled multiplier path for B20 Asset issuers running corporate actions such as stock splits and in-kind dividends. The change moves the multiplier setter from an instant path to a scheduled path aligned with ERC-8056. The change applies only to B20 Asset (Cobalt hardfork, upcoming).

Previously, B20 Asset multiplier updates were applied immediately through the `updateMultiplier` function. The new scheduled path allows issuers to define a new multiplier in advance and activate it at a specific future timestamp. This supports planned corporate actions and aligns B20 multiplier behavior with the ERC-8056 standard.

The two use cases enabled are stock splits and in-kind dividends. The legacy `updateMultiplier` instant setter is retained as an emergency failsafe if a wrong value is passed.

## Motivation

The change solves the problem that B20 Asset did not have a scheduled setter for multiplier updates. Before this change, multiplier changes used only the instant `updateMultiplier` path, which does not allow issuers to schedule changes in advance.

The ERC-8056 standard (https://eips.ethereum.org/EIPS/eip-8056) defines a standard for scheduling changes to an RWA token. This change conforms B20 Asset to that standard for scheduling multipliers.

## Background

### ERC-8056

ERC-8056 (https://eips.ethereum.org/EIPS/eip-8056) is an Ethereum Improvement Proposal that creates a standard for scheduling changes to an RWA token. The standard defines a core interface and optional extensions for UI balance queries, conversion helpers, and pending multiplier reads.

### B20 Asset

B20 Asset is an RWA token standard that conforms to the ERC-20 specification. Prior to this change, B20 Asset included these multiplier-related functions:

- `updateMultiplier(uint256 newMultiplier)`: Applies the multiplier immediately
- `toScaledBalance(uint256)`: Legacy read/conversion alias that predates ERC-8056 naming
- `toRawBalance(uint256)`: Legacy read/conversion alias that predates ERC-8056 naming

### Terminology

- **WAD_PRECISION**: Fixed-point precision used to scale the multiplier, equal to `1e18` (18 decimal places). `1e18 = 1.0` multiplier.
- **UI multiplier**: The cosmetic multiplier that rescales displayed balances without minting, transferring, or rewriting raw balances (ERC-8056 terminology).
- **Raw balance**: The canonical on-chain token amount stored in the contract.
- **Scaled balance / UI balance**: The derived display balance calculated as `rawBalance * multiplier / WAD_PRECISION`.
- **Pending update**: A scheduled multiplier change that has not yet reached its `effectiveAt` timestamp.
- **OPERATOR_ROLE**: Pre-existing role required to call `updateUIMultiplier`, `cancelUIMultiplierUpdate`, and `updateMultiplier`. This role is not introduced by this change and already gates `announce`.

## Specs

### Interface Changes

#### Functions

| Symbol | Selector | Status | Notes |
| --- | --- | --- | --- |
| `updateUIMultiplier(uint256,uint256)` | `0x628e600f` | new | Canonical scheduled setter for corporate actions. |
| `cancelUIMultiplierUpdate()` | `0x2c97a0f0` | new | Cancels the single live pending update. |
| `newUIMultiplier()` | `0xdc767007` | new | ERC-8056 pending-schedule read (target multiplier). |
| `effectiveAt()` | `0x97a4064f` | new | ERC-8056 pending-schedule read (flip timestamp). |
| `totalSupplyUI()` | `0x9bea6429` | new | ERC-8056 Balances extension. |
| `MAX_UI_MULTIPLIER()` | `0x785c0cf0` | new | Reads the multiplier ceiling (`type(uint128).max`) without triggering the revert path. |
| `supportsInterface(bytes4)` | `0x01ffc9a7` | new | ERC-165 feature detection. |
| `uiMultiplier()` | `0xa60bf13d` | new alias | ERC-8056 core naming. Aliases `multiplier()`; same effective value. |
| `balanceOfUI(address)` | `0x437a9958` | new alias | ERC-8056 Balances extension. Aliases `scaledBalanceOf(address)`; same value. |
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
| `UIMultiplierUpdated(uint256,uint256,uint256)` | `0x2205df4534432b2f60654a3fdb48737ffdaf3e9edb1a498bd985bc026b15b055` | new | ERC-8056 canonical multiplier-change event. Emitted by both setters. |
| `UIMultiplierUpdateCancelled(uint256,uint256)` | `0x883856335ba5f60c18b9817c4505d3c7d3f6223dcf39516b30c508c46a5e1cad` | new | Signals a cleared pending update (via cancel or a superseding instant setter). |
| `MultiplierUpdated(uint256)` | `0x4dbe4840d7465bd162f67814cea0b519567a2e0e578bcde61e7f4ced361e5a3d` | deprecated-still-emitted | Legacy event. Emitted only by the instant setter (`updateMultiplier`) alongside `UIMultiplierUpdated`. The scheduled setter emits only `UIMultiplierUpdated`. |

#### Errors

| Symbol | Selector | Status | Notes |
| --- | --- | --- | --- |
| `EffectiveAtInPast(uint256)` | `0x14119cf6` | new | Thrown when `effectiveAt <= block.timestamp`. |
| `EffectiveAtTooFar(uint256)` | `0x1ce214fa` | new | Thrown when `effectiveAt > type(uint64).max`. |
| `UIMultiplierUpdateExists(uint256)` | `0x4481a68e` | new | Thrown when a live pending update already exists. |
| `UIMultiplierUpdateDoesNotExist()` | `0xa7d6a5ca` | new | Thrown when cancel is called with no live pending update. |
| `InvalidMultiplier()` | `0x6f12f3dc` | unchanged | Zero or above-ceiling guard. Now also thrown by `updateUIMultiplier`. |

#### Interface IDs advertised via `supportsInterface`

| Interface ID | Interface | Status |
| --- | --- | --- |
| `0x01ffc9a7` | `IERC165` | new advertisement |
| `0xa60bf13d` | `IScaledUIAmount` (ERC-8056 core) | new advertisement |
| `0x4bd27648` | `IScaledUIAmountNewUIMultiplier` (ERC-8056 pending) | new advertisement |
| `0xd890fd71` | `IScaledUIAmountBalances` (ERC-8056 optional) | new advertisement |
| `0x57854fc3` | `IScaledUIAmountConversion` (ERC-8056 optional) | new advertisement |

The following code snippet shows the net additions to the `IB20Asset` interface surface. The legacy `updateMultiplier`, `toScaledBalance`, and `toRawBalance` functions remain but are marked deprecated.

```solidity
// ERC-8056 core (IScaledUIAmount)
function uiMultiplier() external view returns (uint256);

// ERC-8056 pending (IScaledUIAmountNewUIMultiplier)
function newUIMultiplier() external view returns (uint256);
function effectiveAt() external view returns (uint256);

// ERC-8056 balances (IScaledUIAmountBalances)
function balanceOfUI(address account) external view returns (uint256);
function totalSupplyUI() external view returns (uint256);

// ERC-8056 conversion (IScaledUIAmountConversion)
function toUIAmount(uint256 rawAmount) external view returns (uint256);
function fromUIAmount(uint256 uiAmount) external view returns (uint256);

// ERC-165
function supportsInterface(bytes4 interfaceId) external view returns (bool);

// Constants
function MAX_UI_MULTIPLIER() external view returns (uint256);

// New scheduled path
function updateUIMultiplier(uint256 newMultiplier, uint256 effectiveAt) external;
function cancelUIMultiplierUpdate() external;

// Deprecated — retained for back-compat
function updateMultiplier(uint256 newMultiplier) external;
function toScaledBalance(uint256 rawBalance) external view returns (uint256);
function toRawBalance(uint256 scaledBalance) external view returns (uint256);
```

### Behavioural Changes

#### Execution Flow

**Old behavior:**
- `updateMultiplier(uint256)` applied the multiplier immediately.
- The change emitted the deprecated `MultiplierUpdated(uint256)` event.

**New behavior:**
- `updateUIMultiplier(uint256 newMultiplier, uint256 effectiveAt)` is the canonical path for routine corporate actions.
- The caller schedules one pending multiplier update for a future timestamp.
- The pending update becomes effective lazily on read when `block.timestamp >= effectiveAt`.
- No extra event fires at maturation time. Off-chain systems must read `uiMultiplier()` or watch the pending schedule.
- `newUIMultiplier()` and `effectiveAt()` expose the live pending update.
- `cancelUIMultiplierUpdate()` clears the live pending update and emits `UIMultiplierUpdateCancelled(uint256,uint256)`.

**Compatibility behavior:**
- `updateMultiplier(uint256)` remains callable as a deprecated instant failsafe.
- The instant setter applies the multiplier immediately and clears any live pending update.
- If it clears a live pending update, it emits `UIMultiplierUpdateCancelled(...)` first, then emits the legacy `MultiplierUpdated(uint256)` event and the canonical `UIMultiplierUpdated(uint256,uint256,uint256)` event.

#### Access Control

All three write functions — `updateUIMultiplier`, `cancelUIMultiplierUpdate`, and `updateMultiplier` — require `OPERATOR_ROLE`. `OPERATOR_ROLE` is pre-existing (not introduced by this change) and already gates `announce`.

#### Gas Cost Implications

Every scaled-view read (`uiMultiplier`, `multiplier`, `balanceOfUI`, `scaledBalanceOf`, `toUIAmount`, `fromUIAmount`, `totalSupplyUI`) now includes an extra `SLOAD` for the pending slot plus a `block.timestamp` compare. Raw `balanceOf` is unchanged.

#### Storage Layout Changes

- New field `PendingMultiplier pending` appended to the `base.b20.asset` ERC-7201 namespace.
  - Namespace location: `0xfdc6d4552d1286ade4d9facdbf0fb50d2ec9b89a90e104f26fd277585e374b00`.
  - Placed at `PENDING_OFFSET = 4`.
- Packed into a single 256-bit slot:
  - Bits 0-127: `uint128 multiplier` (target).
  - Bits 128-191: `uint64 effectiveAt` (flip timestamp).
  - Bits 192-255: unused (32 bytes free for future packing).
- Additive change; pre-existing offsets 0-3 are unchanged:
  - offset 0: `uint8 decimals`
  - offset 1: `uint256 multiplier` (stored `0` still interpreted as `WAD_PRECISION` on read)
  - offset 2: `mapping usedAnnouncementIds`
  - offset 3: `mapping extraMetadata`
- Must match the `base/base` Rust precompile slot-for-slot (AGENTS.md invariant).

### ERC-8056 View Aliases

- `uiMultiplier()` returns the same value as `multiplier()`.
- `toUIAmount(raw)` returns the same value as `toScaledBalance(raw)`. `fromUIAmount(ui)` returns the same value as `toRawBalance(ui)`.
- `balanceOfUI(account)` returns the same value as `scaledBalanceOf(account)`.
- `totalSupplyUI()` equals `totalSupply() * uiMultiplier() / WAD_PRECISION`.

### Examples

`updateUIMultiplier(newMultiplier, effectiveAt)` is the canonical path for corporate actions such as stock splits and reinvested dividends. Only one pending update can be live at a time.

1. **Schedule**: Call `updateUIMultiplier(newMultiplier, effectiveAt)`. This requires `OPERATOR_ROLE`, and `effectiveAt` must be strictly in the future.
2. **Read the pending update**: While it is live, `newUIMultiplier()` returns the scheduled target, `effectiveAt()` returns the flip timestamp, and `uiMultiplier()` / `multiplier()` still return the current value.
3. **Let it mature**: Once `block.timestamp >= effectiveAt`, `uiMultiplier()` / `multiplier()` flip on read. No event fires at maturation.
4. **Or cancel it**: `cancelUIMultiplierUpdate()` clears a live pending update and emits `UIMultiplierUpdateCancelled(cancelledMultiplier, cancelledEffectiveAt)`.

To reorder overlapping actions, cancel and reschedule atomically in one announcement:

```solidity
announce([cancelUIMultiplierUpdate(), updateUIMultiplier(...)], ...)
```

## Design Decisions & Alternatives Considered

The design retains the instant setter (`updateMultiplier`) as a deprecated dialable failsafe.

**Rationale:**
- It is the only on-chain recourse to correct or supersede a scheduled multiplier without waiting for `effectiveAt`.
- Cancel-then-schedule cannot fix a bad scheduled value if the correction must apply immediately.
- Removing it would leave operators no emergency override if a wrong `newMultiplier` or wrong `effectiveAt` were scheduled.

## Migration Steps

### Backwards-compatible

`updateMultiplier`, `toScaledBalance`, and `toRawBalance` continue to work unchanged. No action is required if you do not need scheduled multiplier behavior yet.

### No breaking changes

All existing selectors, events, and errors remain dialable. The legacy `MultiplierUpdated` event is still emitted by the instant setter.

### To adopt the scheduled path

1. Replace direct calls to `updateMultiplier(newMultiplier)` with `updateUIMultiplier(newMultiplier, effectiveAt)` for routine corporate actions.
2. Use `newUIMultiplier()` and `effectiveAt()` to read the pending schedule.
3. Use `cancelUIMultiplierUpdate()` to clear a pending update before it matures.
4. For emergency corrections, retain the ability to call `updateMultiplier(newMultiplier)` which immediately applies the change and clears any pending update.
5. Update off-chain indexers to listen for `UIMultiplierUpdated` instead of (or in addition to) the deprecated `MultiplierUpdated` event.
6. Update display logic to prefer ERC-8056 naming: `uiMultiplier()`, `balanceOfUI()`, `toUIAmount()`, `fromUIAmount()`, `totalSupplyUI()`.

### No storage migration

The pre-existing multiplier storage at offset 1 is untouched. The new `PendingMultiplier` slot at offset 4 is additive and starts in the no-pending state (`effectiveAt = 0`).