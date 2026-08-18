# Seize surface and `burnBlocked` deprecation

- **Feature Name**: seize
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Seize surface + burnBlocked deprecation

## Summary

This change adds a `seizeWithMemo` function to the shared `IB20` interface. Both B20 Asset and B20 Stablecoin inherit the function, and neither variant adds variant-specific logic.

Today, an operator seizes an asset with a three-step workaround: block the account, call `burnBlocked`, then mint the same amount to a new holder. This destroys the balance and reissues it. `seizeWithMemo` replaces the workaround with a single admin call that reassigns the balance directly from one account to another.

**Compatibility promise**: `burnBlocked` remains fully dialable with its existing behavior. No removal is planned. This deprecation is permanent, not a phased removal. BOP-471, the re-merge ticket, was canceled. `seizeWithMemo` is new, additive surface, and nothing existing is broken.


## Motivation

Compliant asset issuers need freeze and seize models. Today, the standard achieves seize with a `block` + `burnBlocked` + `mint` sequence that destroys the balance and then reissues it. `seizeWithMemo` replaces that workaround with a direct balance reassignment from `from` to `to`. The reassignment neither burns nor mints, so `totalSupply` is unchanged. The function emits a single, purpose-built `Seized` event.

Burn functionality must be explicitly distinct from seize functionality. The two operations may be gated on different policies.

The current seize workaround takes three steps and does not record that a seize occurred:

1. Configure `from` as blocked under `TRANSFER_SENDER_POLICY`. This is the same policy that `burnBlocked` reads today, verified against `IB20.sol`.
2. Burn the assets. This reduces token supply.
3. Mint the assets to complete the seize.

The workaround emits a burn event and a mint event. No event indicates that a seize occurred.

The proposed functionality reduces the operation to two actions:

1. Add the account to the policy so it can be seized from.
2. Call the `seizeWithMemo` function. This emits a `Seized` event.

## Background

Read the following concepts before the Specs section.

**B20 Asset and B20 Stablecoin** are native tokens launched on B20. Both have built-in roles and access controls. Both gate their functions with the policy registry and policy functionality.

**Policy Registry** is a singleton precompile contract. Its responsibility is to return `isAuthorized(policyId, account)`. This signature is verified against `IPolicyRegistry.sol`. It is not `isAllowed(address, true)`. B20 uses the policy registry to gate operations. B20 passes the stored policy ID and the account to check.

## Specs

### Interface Changes

The following table maps the affected symbols. All selectors and topic0 values were verified with `cast sig`, `cast keccak`, and `cast sig-event` against `src/interfaces/IB20.sol` and `src/lib/B20Constants.sol` on 2026-08-18.

| Symbol | Selector / topic0 | Status | Notes |
| --- | --- | --- | --- |
| `burnBlocked(address,uint256)` | `0xec0cf3dc` | deprecated-dialable | Behavior unchanged. No removal date committed. |
| `error AccountNotBlocked(address)` | `0x64a5cb46` | unchanged | Still exclusive to `burnBlocked`. |
| `event BurnedBlocked(address,address,uint256)` | topic0 `0x0b552e96653fd6842da37c477005d3b5c08a8c7d3631b1f43787b2dc9a1006a3` | unchanged | Still exclusive to `burnBlocked`. |
| `seizeWithMemo(address,address,uint256,bytes32)` | `0xf916d81b` | new | Single-call admin seize. Reassigns the balance of `from` to `to`. |
| `SEIZE_ROLE()` | `0x3c7e9ba5` | new | Role value `0x3469b8b0d89e9604f8510ed143f74a8336d22955d4f83e23bf53d9414e27f432`. |
| `SEIZE_HOLDER_POLICY()` | `0xb279d311` | new | Policy value `0x1497ab2b67ebb0a75dd9cdd6aec9f0e64620e6b87e911af7a088ac12e58d9ef2`. Gates who is seizable. Membership is inverted: an account is seizable if it is NOT authorized. |
| `SEIZE_RECEIVER_POLICY()` | `0xb31da27f` | new | Policy value `0xbf15b19caf5c77422c038bc25f26b8b815c3a14f6d04c6616076b81bcfe07b3d`. Gates the seize destination. An unset slot means always-allow. |
| `event Seized(address indexed caller, address indexed from, address indexed to, uint256 amount)` | topic0 `0xa9aec5d8b86e2fa2fd6ac3af62f2622e3dfdab1967d4cbbb56a5df7d74cb887c` | new | |
| `error AccountNotSeizable(address)` | `0x91dbbc8d` | new | |
| `PausableFeature.SEIZE` | — | new | Dedicated pause vector, independent of `BURN`. |

The new seize surface adds the following declarations to `IB20`.

```solidity
// Pausable operation classes. The SEIZE member is appended after TRANSFER, MINT, and BURN.
enum PausableFeature {
    TRANSFER,
    MINT,
    BURN,
    SEIZE
}

// Reverts when `from` is currently authorized under SEIZE_HOLDER_POLICY (not a member of the seizable set).
error AccountNotSeizable(address account);

// Emitted by seizeWithMemo, in addition to Transfer(from, to, amount) and Memo(caller, memo).
event Seized(address indexed caller, address indexed from, address indexed to, uint256 amount);

// Role required to call seizeWithMemo.
function SEIZE_ROLE() external view returns (bytes32);

// Policy slot consulted against `from` by seizeWithMemo.
function SEIZE_HOLDER_POLICY() external view returns (bytes32);

// Policy slot consulted against `to` by seizeWithMemo. An unset slot reads as always-allow.
function SEIZE_RECEIVER_POLICY() external view returns (bytes32);

// Seizes `amount` of `from`'s balance and reassigns it to `to` in a single admin operation.
function seizeWithMemo(address from, address to, uint256 amount, bytes32 memo) external;
```

### Behavioural Changes

`seizeWithMemo(from, to, amount, memo)` applies its guards and emits its events in a fixed order. This order is verified against the reference implementation in `MockB20.sol` and the natspec in `IB20.sol`.

1. `whenNotPaused(SEIZE)`. If the `SEIZE` vector is paused, the call reverts `ContractPaused(SEIZE)`.
2. `onlyRole(SEIZE_ROLE)`. If the caller does not hold `SEIZE_ROLE`, the call reverts `AccessControlUnauthorizedAccount`.
3. If `to == address(0)`, the call reverts `InvalidReceiver`.
4. If `from == address(0)`, the call reverts `InvalidSender`.
5. If `from == to`, the call reverts `InvalidReceiver`. This rejects self-seize.
6. If `from` IS authorized under `SEIZE_HOLDER_POLICY`, the call reverts `AccountNotSeizable`. An account is seizable only when it is NOT authorized under this policy.
7. If `to` is NOT authorized under `SEIZE_RECEIVER_POLICY`, the call reverts `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)`.
8. If the balance of `from` is less than `amount`, the call reverts `InsufficientBalance`.
9. The call emits, in order: `Transfer(from, to, amount)`, then `Memo(caller, memo)`, then `Seized(caller, from, to, amount)`.

`seizeWithMemo` is an admin operation. It skips the allowance check and all three transfer-side policies: `TRANSFER_SENDER_POLICY`, `TRANSFER_RECEIVER_POLICY`, and `TRANSFER_EXECUTOR_POLICY`.

The `PausableFeature.SEIZE` vector pauses `seizeWithMemo` independently. Pausing `SEIZE` does not pause `burnBlocked` or transfer operations. Pausing `BURN` or `TRANSFER` does not pause seizing.

Seize is a transfer, not a burn. The balance moves from `from` to `to`, and `totalSupply` is unchanged. This is the key behavioral difference from `burnBlocked`. `burnBlocked` sends the balance to `address(0)` and reduces supply.

### Examples

**Before**: the block, burn, and mint workaround. This path is still available and is deprecated.

1. Configure `from` as blocked under `TRANSFER_SENDER_POLICY`.
2. Call `burnBlocked(from, amount)`. This burns the balance of `from` and is gated by `BURN_BLOCKED_ROLE`.
3. Call `mint(treasury, amount)`. This separately reissues the same amount and is gated by `MINT_ROLE`.

This path emits `Transfer(from, 0, amount)`, then `BurnedBlocked`, then `Transfer(0, treasury, amount)`. These are two independent operations. No single event ties the burn to the reissue.

**After**: the new single call.

1. Configure `from` as NOT authorized under `SEIZE_HOLDER_POLICY`. This marks the account as seizable.
2. Call `seizeWithMemo(from, treasury, amount, memo)`. This is gated by `SEIZE_ROLE`.

This path emits `Transfer(from, treasury, amount)`, then `Memo(caller, memo)`, then `Seized(caller, from, treasury, amount)`.

## Design Decisions & Alternatives Considered

**Final shipped shape**: `seizeWithMemo` and `burnBlocked` use fully independent policy slots and pause vectors.

- `seizeWithMemo` uses the new `SEIZE_HOLDER_POLICY` for `from`, the new `SEIZE_RECEIVER_POLICY` for `to`, the new `SEIZE_ROLE`, and the new `PausableFeature.SEIZE`.
- `burnBlocked` retains `TRANSFER_SENDER_POLICY`, `BURN_BLOCKED_ROLE`, and the `BURN` pause vector, all unchanged.

**Shared seize-policy approach (rejected)**: A shared policy for burn and seize was rejected because the two operations have different effects. `burnBlocked` destroys supply, and `seizeWithMemo` reassigns balances. `burnBlocked` therefore remains independent, and no `burnBlockedWithMemo` variant is included.

**Function naming (`transferFromBlockedWithMemo` rejected)**: The name `transferFromBlockedWithMemo` was also considered. The name `seizeWithMemo` was chosen because it explicitly defines the intent.

## Migration Steps

This change is backwards-compatible and introduces no breaking changes:

- `burnBlocked` continues to work unchanged. No action is required if you do not need seize behavior yet.
- All existing selectors, events, and errors remain dialable.

To adopt `seizeWithMemo`, complete the following steps:

1. Grant `SEIZE_ROLE` to the account or accounts that should be able to seize. If no account holds `SEIZE_ROLE`, no one can seize.
2. Configure `SEIZE_HOLDER_POLICY` so that the accounts you want to be seizable are NOT authorized under it. If you configure no policy, the unset slot means always-allow, and no account is seizable.
3. Optionally, configure `SEIZE_RECEIVER_POLICY` to restrict where seized funds may land. The unset slot defaults to always-allow, so an unallowlisted treasury still works.

To reproduce the destroy-supply outcome of `burnBlocked` with seize, take two steps. `seizeWithMemo` alone does not reduce `totalSupply`. First, seize to a treasury or self address. Then call `burn(amount)` from that address if you want the supply destroyed.

No storage migration is required. The storage and behavior of `burnBlocked` are untouched by this change.
