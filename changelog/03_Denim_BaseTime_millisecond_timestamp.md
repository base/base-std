# BaseTime Millisecond Timestamp

- **Feature Name**: millisecond_timestamp
- **Start Date**: 2026-10-08
- **Authors**: Francis Li
- **Title**: BaseTime Millisecond Timestamp

## Summary

Denim installs the BaseTime predeploy at `0x4200000000000000000000000000000000000030`. It exposes the millisecond component of the current block timestamp, so contracts can read block time at millisecond precision.

base-std adds the read-only `IBaseTime` interface and a typed handle, `StdPredeploys.BASE_TIME`. Read `StdPredeploys.BASE_TIME.timestampMs()` for the full millisecond timestamp.

## Motivation

`block.timestamp` has second precision, but from Denim a block's timestamp carries a sub-second component. Contracts that need the exact block time, such as auctions, rate limits, or time-weighted pricing, have no way to read the millisecond component from the EVM alone.

## Background

BaseTime is a proxied predeploy: Solidity bytecode at a `0x4200…` address, not a native precompile. That is why its handle lives in a new `StdPredeploys` library instead of `StdPrecompiles`.

The protocol writes the millisecond component once per Denim block, through a depositor-only setter called by the block-scoped deposit at `tx[1]`. Before that deposit executes, the stored value is still the previous block's.

## Specs

### Interface Changes

New interface `src/interfaces/IBaseTime.sol` and library `src/StdPredeploys.sol`:

```solidity
interface IBaseTime {
    function timestampMillisPart() external view returns (uint16);
    function timestampMs() external view returns (uint64);
    function version() external view returns (string memory);
}

library StdPredeploys {
    address internal constant BASE_TIME_ADDRESS = 0x4200000000000000000000000000000000000030;
    IBaseTime internal constant BASE_TIME = IBaseTime(BASE_TIME_ADDRESS);
}
```

| Symbol | Selector / Topic0 | Status | Notes |
| ------ | ----------------- | ------ | ----- |
| `timestampMillisPart()` | `0x7b2fea99` | NEW (view) | Millisecond component: `0`, `200`, `400`, `600`, or `800`; never reverts |
| `timestampMs()` | `0x5745a677` | NEW (view) | `block.timestamp * 1000 + timestampMillisPart()`; never reverts |
| `version()` | `0x54fd4d50` | NEW (view) | Returns `"1.0.0"` |

The depositor-only setter and its errors are protocol-internal and are not part of `IBaseTime`.

### Behavioural Changes

- No existing selector, event, error, or storage slot changes. The predeploy is new.
- Storage: `uint16 timestampMillisPart` in the low-order 2 bytes of slot 0.
- Until the block's `tx[1]` deposit executes (for example, during the `tx[0]` L1-info deposit), `timestampMs()` combines the current block's seconds with the previous block's millisecond component.

### Examples

```solidity
import {StdPredeploys} from "base-std/StdPredeploys.sol";

uint64 nowMs = StdPredeploys.BASE_TIME.timestampMs();
// block.timestamp == 1_800_000_000, timestampMillisPart() == 400
// nowMs == 1_800_000_000_400
```

## Design Decisions & Alternatives Considered

- **Read-only interface.** Only the protocol deposit can write the value, so exposing the setter would give integrators a selector that always reverts for them.
- **Separate `StdPredeploys` library.** Predeploys are EVM bytecode and precompiles are native code; keeping them in separate libraries keeps that distinction visible at the call site.
- **Slot-0 mock layout.** `MockBaseTime` stores the `uint16` at slot 0 instead of an ERC-7201 namespace, matching the real contract's layout so `vm.store`-based tests behave the same against either.

## Migration Steps

- Additive: no existing integration changes.
- After Denim activates, read `StdPredeploys.BASE_TIME.timestampMs()` for millisecond block time.
- Code that runs before `tx[1]` in a block, such as the L1-info deposit, sees the previous block's millisecond component.
- Before Denim, the predeploy has no implementation and calls to it revert; don't depend on it on a chain where Denim hasn't activated.
