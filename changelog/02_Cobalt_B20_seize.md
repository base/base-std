# Seize Policy

- **Feature Name**: seize
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Seize surface + burnBlocked deprecation

## Summary

This change adds the `seizeWithMemo` function to the shared `IB20` interface. Both B20 Asset and B20 Stablecoin inherit this function with no variant-specific logic.

The original workflow to seize an asset required three steps: block the sender, call `burnBlocked`, then mint to the seizure account. This workflow destroys and then reissues supply. The `seizeWithMemo` function replaces this with a single administrative call that reassigns the balance directly from the source account to the destination account.

The `burnBlocked` function remains available but is now deprecated. It continues to burn blocked assets through the existing flow.

## Motivation

Burn functionality and seize functionality must be explicitly distinct because they may be gated on different policies. Compliant asset issuers require freeze-and-seize models.

Currently, the system achieves seizure through a workaround that uses `burnBlocked` to burn the asset and `mint` to reissue it to the seizure account. This workaround has three steps:

1. Configure the `from` account as blocked under `TRANSFER_SENDER_POLICY` (the same policy that `burnBlocked` reads today — verified against `IB20.sol`)
2. Burn assets from the `from` account — this affects token supply
3. Mint assets to the seizure account

This process emits a `BurnedBlocked` event and a `Transfer` event for the mint. It does not emit an event that indicates a seizure occurred.

The main issues with this approach are:

- The events emitted are misleading for burning and minting operations
- The token supply is affected when assets are burned

The proposed `seizeWithMemo` function replaces this workaround with a direct transfer to the seizure account that emits a `Seized` event. The new flow:

1. Add a policy to define which accounts are seizable
2. Call the `seizeWithMemo` function — this emits a `Seized` event

This change makes seizure functionality and burning functionality explicitly distinct.

## Background

### B20 Asset and B20 Stablecoin

B20 Asset and B20 Stablecoin are Base-native token contracts that extend ERC-20 with role-gated administrative functions and policy-gated operation checks. Each token stores fine-grained policy slots, keyed by operation and actor position, and consults the PolicyRegistry through `isAuthorized(policyId, account)` to decide whether a given account is allowed for that slot. For example, transfer flows can independently gate the sender, receiver, and executor, while other operations use their own dedicated policy slots, such as mint receiver and seize holder/receiver. This design separates access control from compliance logic: roles determine who may call privileged methods, and policy slots determine which accounts may participate in a given token operation.

### Policy Registry

The Policy Registry is a singleton precompile contract. Its responsibility is to return `isAuthorized(policyId, account)`. B20 uses the Policy Registry to gate operations by passing the stored policy ID and the account to check.

## Specs

### Interface Changes

The following changes are made to the interface. Old-to-new mappings for selectors and topic0 values are verified via `cast sig`/`cast keccak` against `src/interfaces/IB20.sol` and `src/lib/B20Constants.sol`.

| Symbol | Selector / Topic0 | Status | Notes |
|--------|-------------------|--------|-------|
| `burnBlocked(address,uint256)` | `0xec0cf3dc` | **deprecated-dialable** | Unchanged behavior, no removal date committed |
| `AccountNotBlocked(address)` | `0x64a5cb46` | unchanged | Still exclusive to `burnBlocked` |
| `BurnedBlocked(address,address,uint256)` | `0x0b552e96653fd6842da37c477005d3b5c08a8c7d3631b1f43787b2dc9a1006a3` | unchanged | Still exclusive to `burnBlocked` |
| `seizeWithMemo(address,address,uint256,bytes32)` | `0xf916d81b` | NEW | Single-call admin seize, reassigns `from`'s balance to `to` |
| `SEIZE_ROLE()` | `0x3c7e9ba5` | NEW | Role value: `0x3469b8b0d89e9604f8510ed143f74a8336d22955d4f83e23bf53d9414e27f432` |
| `SEIZE_HOLDER_POLICY()` | `0xb279d311` | NEW | Value: `0x1497ab2b67ebb0a75dd9cdd6aec9f0e64620e6b87e911af7a088ac12e58d9ef2` — gates who is seizable; inverted membership (seizable if NOT authorized) |
| `SEIZE_RECEIVER_POLICY()` | `0xb31da27f` | NEW | Value: `0xbf15b19caf5c77422c038bc25f26b8b815c3a14f6d04c6616076b81bcfe07b3d` — gates seizure destination; unset slot = always-allow |
| `Seized(address indexed caller, address indexed from, address indexed to, uint256 amount)` | `0xa9aec5d8b86e2fa2fd6ac3af62f2622e3dfdab1967d4cbbb56a5df7d74cb887c` | NEW | Seized event |
| `AccountNotSeizable(address)` | `0x91dbbc8d` | NEW | New error |
| `PausableFeature.SEIZE` | — | NEW | Dedicated pause vector, independent of `BURN` |

The following code snippet shows the net additions to the `IB20` interface surface. The `burnBlocked` function and its associated error/event remain but are marked deprecated.

```solidity
// PausableFeature enum — SEIZE appended
enum PausableFeature {
    TRANSFER,
    MINT,
    BURN,
    SEIZE
}

error AccountNotSeizable(address account);

event Seized(address indexed caller, address indexed from, address indexed to, uint256 amount);

function SEIZE_ROLE() external view returns (bytes32);

function SEIZE_HOLDER_POLICY() external view returns (bytes32);
function SEIZE_RECEIVER_POLICY() external view returns (bytes32);

/// @notice Seizes `amount` of `from`'s balance and reassigns it to `to` in a single admin operation.
///         Emits `Transfer`, then `Memo`, then `Seized`.
function seizeWithMemo(address from, address to, uint256 amount, bytes32 memo) external;

// DEPRECATED — retained for back-compat
function burnBlocked(address from, uint256 amount) external;
```

### Behavioural Changes

#### New function: `seizeWithMemo`

The `seizeWithMemo(from, to, amount, memo)` function executes the following steps:

1. Check that `SEIZE` is not paused, else revert `ContractPaused(SEIZE)`.
2. Check that the caller has `SEIZE_ROLE`, else revert `AccessControlUnauthorizedAccount`.
3. Reject zero or self destinations, else revert `InvalidReceiver`.
4. Reject zero source, else revert `InvalidSender`.
5. Require `from` to be not authorized under `SEIZE_HOLDER_POLICY`, else revert `AccountNotSeizable`.
6. Require `to` to be allowed by `SEIZE_RECEIVER_POLICY`, else revert `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)`.
7. Check balance, else revert `InsufficientBalance`.
8. Emit `Transfer`, then `Memo`, then `Seized`.

The function does not check allowance on the three transfer-side policies: `TRANSFER_SENDER_POLICY`, `TRANSFER_RECEIVER_POLICY`, or `TRANSFER_EXECUTOR_POLICY`.

A dedicated pause vector `PausableFeature.SEIZE` pauses `seizeWithMemo`. When paused, the function returns `ContractPaused(SEIZE)`.

Seizure is a transfer, not a burn. The balance moves from `from` to `to` and `totalSupply` remains unchanged. This is the key behavioral difference from `burnBlocked`, which sends to `address(0)` and reduces supply.

#### Storage layout change

A packed `seizePolicyIds` slot is added for `SEIZE_HOLDER_POLICY` and `SEIZE_RECEIVER_POLICY`. This change is additive. The `burnBlocked` storage remains unchanged.

### Examples

#### Before (old block+burn+mint workaround, still available, deprecated)

1. Configure `from` as blocked under `TRANSFER_SENDER_POLICY`
2. Call `burnBlocked(from, amount)` — burns `from`'s balance, gated by `BURN_BLOCKED_ROLE`
3. Call `mint(treasury, amount)` — separately reissues the same amount, gated by `MINT_ROLE`
4. Emits `Transfer(from, 0, amount)` + `BurnedBlocked` + `Transfer(0, treasury, amount)` — two independent operations, no single event ties the burn to the reissue

#### After (new, single call)

1. Configure `from` as NOT authorized under `SEIZE_HOLDER_POLICY` (i.e. blocked)
2. Call `seizeWithMemo(from, treasury, amount, memo)` — gated by `SEIZE_ROLE`
3. Emits `Transfer(from, treasury, amount)` → `Memo(caller, memo)` → `Seized(caller, from, treasury, amount)`

## Design Decisions & Alternatives Considered

### Final shipped shape

The `seizeWithMemo` and `burnBlocked` functions use fully independent policy slots and pause vectors.

- `seizeWithMemo` uses the new `SEIZE_HOLDER_POLICY` (for `from`) and `SEIZE_RECEIVER_POLICY` (for `to`), the new `SEIZE_ROLE`, and the new `PausableFeature.SEIZE`.
- `burnBlocked` retains `TRANSFER_SENDER_POLICY`, `BURN_BLOCKED_ROLE`, and the `BURN` pause vector unchanged.

Seize operations are rare, so the reserved lane in the transfer packed policy slot was not reused for seizure. That lane is kept open for a possible future transfer-side optimization where another hot-path transfer policy could be packed into the existing transfer slot without adding a second `SLOAD`. Because seizure is a cold-path / rare-path operation, it gets its own packed `seizePolicyIds` slot.

### Function Naming Alternatives

The shared seize-policy approach was rejected because burning and seizing have different effects: `burnBlocked` destroys supply, while `seizeWithMemo` reassigns balances. `burnBlocked` therefore remains independent, and no `burnBlockedWithMemo` variant is included.

The name `transferFromBlockedWithMemo` was also considered. `seizeWithMemo` was chosen because it explicitly defines the intent.

## Migration Steps

### Backwards-compatible

`burnBlocked` continues to work unchanged. No action is required if you do not need seizure behavior yet.

### No breaking changes

All existing selectors, events, and errors remain dialable.

### To adopt `seizeWithMemo`

1. Grant `SEIZE_ROLE` to the account(s) that should be able to seize. With no `SEIZE_ROLE` holders, no one can seize.
2. Configure `SEIZE_HOLDER_POLICY` so the accounts you want seizable are NOT authorized under it. With no policy configured (unset = always-allow), no account is seizable.
3. Optionally configure `SEIZE_RECEIVER_POLICY` to restrict where seized funds may land. Unset defaults to always-allow (for example, an unallowlisted treasury still works).

### To reproduce `burnBlocked`'s destroy-supply outcome with seizure

`seizeWithMemo` alone does not reduce `totalSupply`. Seize to a treasury or self address, then call `burn(amount)` from that address if you want the supply destroyed.

### No storage migration

`burnBlocked`'s storage and behavior are untouched by this change.