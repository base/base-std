# Seize surface + burnBlocked deprecation

- **Feature Name**: seize
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Seize surface + burnBlocked deprecation

## Summary

Compliant asset issuers need freeze and seize models. This change adds `seizeWithMemo` to the shared `IB20` interface. Both B20 Asset and B20 Stablecoin inherit this function with no variant-specific logic. The original flow to seize an asset required three steps: block the account, call `burnBlocked`, then mint to reissue. The new `seizeWithMemo` function replaces this workaround with a single admin call that reassigns the balance directly. The `burnBlocked` function is deprecated but remains supported with unchanged behavior and no committed removal date.

## Motivation

Compliant asset issuers need freeze and seize models. Burn functionality must be explicitly distinct from seize because they may be gated on different policies.

Today the workaround to achieve a seizure is: call `burnBlocked` to burn the asset (gated by `TRANSFER_SENDER_POLICY`, the same policy that `burnBlocked` reads), then call `mint` to reissue the same amount to the seize account. This approach has two problems. First, the emitted events (burn + mint) misrepresent the operation as a burn. No single event indicates that a seizure occurred. Second, `totalSupply` changes when the balance is burned, then changes again on reissue.

The `seizeWithMemo` function replaces that workaround with a direct transfer to the seize account. It emits a dedicated `Seized` event. This makes seizing and burning explicitly distinct.

## Background

### B20 Asset and B20 Stablecoin

B20 Asset and B20 Stablecoin are Base-native token contracts that extend ERC-20 with role-gated administrative functions and policy-gated operation checks. Each token stores fine-grained policy slots, keyed by operation and actor position. The token consults the Policy Registry through `isAuthorized(policyId, account)` to decide whether a given account is allowed for that slot. For example, transfer flows can independently gate the sender, receiver, and executor. Other operations use their own dedicated policy slots, such as mint receiver and seize holder/receiver. This design separates access control from compliance logic: roles determine who may call privileged methods, and policy slots determine which accounts may participate in a given token operation.

### Policy Registry

The Policy Registry is a singleton precompile contract. Its responsibility is to return `isAuthorized(policyId, account)`. B20 uses the Policy Registry to gate operations by passing the stored policy ID and the account to check.

## Specs

### Interface Changes

The following changes add new functions, events, errors, and role/policy constants to the `IB20` interface. The deprecated `burnBlocked` function and its associated error and event remain but are marked deprecated.

**Deprecated (dialable, unchanged behavior, no removal date committed):**

| Symbol | Selector / topic0 |
|--------|-------------------|
| `burnBlocked(address,uint256)` | `0xec0cf3dc` |
| `error AccountNotBlocked(address)` | `0x64a5cb46` |
| `event BurnedBlocked(address,address,uint256)` | `0x0b552e96653fd6842da37c477005d3b5c08a8c7d3631b1f43787b2dc9a1006a3` |

**New additions:**

| Symbol | Selector / topic0 / value |
|--------|---------------------------|
| `seizeWithMemo(address,address,uint256,bytes32)` | `0xf916d81b` |
| `SEIZE_ROLE()` | `0x3c7e9ba5` (role value `0x3469b8b0d89e9604f8510ed143f74a8336d22955d4f83e23bf53d9414e27f432`) |
| `SEIZE_HOLDER_POLICY()` | `0xb279d311` (value `0x1497ab2b67ebb0a75dd9cdd6aec9f0e64620e6b87e911af7a088ac12e58d9ef2`) |
| `SEIZE_RECEIVER_POLICY()` | `0xb31da27f` (value `0xbf15b19caf5c77422c038bc25f26b8b815c3a14f6d04c6616076b81bcfe07b3d`) |
| `event Seized(address indexed caller, address indexed from, address indexed to, uint256 amount)` | `0xa9aec5d8b86e2fa2fd6ac3af62f2622e3dfdab1967d4cbbb56a5df7d74cb887c` |
| `error AccountNotSeizable(address)` | `0x91dbbc8d` |
| `PausableFeature.SEIZE` | Enum value appended after `BURN` |

The net additions to the `IB20` interface surface are shown below. The `burnBlocked` function and its associated error and event remain but are marked deprecated.

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

**Policy semantics:**

- `SEIZE_HOLDER_POLICY` gates who is seizable. The membership is inverted: an account is seizable when it is **not** authorized under this policy. This mirrors the blocklist semantics of `burnBlocked`'s `TRANSFER_SENDER_POLICY` so the "blocked = seizable" model carries over. An unset slot reads as `0` (always-allow), so no account is seizable until an issuer configures the slot. This is a safe default.

- `SEIZE_RECEIVER_POLICY` gates the seize destination. It mirrors `MINT_RECEIVER_POLICY`: always enforced on the seize destination. An unset slot defaults to always-allow, so an unconfigured token may seize to any destination (a treasury need not be allowlisted).

### Behavioural Changes

**New function `seizeWithMemo(from, to, amount, memo)` execution flow:**

1. Check that `SEIZE` is not paused; else revert `ContractPaused(SEIZE)`.
2. Check that the caller holds `SEIZE_ROLE`; else revert `AccessControlUnauthorizedAccount`.
3. Reject zero or self destinations; else revert `InvalidReceiver`.
4. Reject zero source; else revert `InvalidSender`.
5. Require `from` to be not authorized under `SEIZE_HOLDER_POLICY`; else revert `AccountNotSeizable`.
6. Require `to` to be allowed by `SEIZE_RECEIVER_POLICY`; else revert `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)`.
7. Check balance; else revert `InsufficientBalance`.
8. Emit `Transfer`, then `Memo`, then `Seized`.

The `memo` parameter attaches an on-chain reference (for example, a case ID or legal order) to each seizure for compliance and audit trails. It is surfaced via the `Memo` event.

The `seizeWithMemo` function bypasses all three transfer-side policies (`TRANSFER_SENDER_POLICY`, `TRANSFER_RECEIVER_POLICY`, `TRANSFER_EXECUTOR_POLICY`). A seizure is a privileged admin action gated by `SEIZE_ROLE` and the seize policies, not a peer transfer. Therefore transfer-side compliance gating does not apply.

A dedicated pause vector `PausableFeature.SEIZE` pauses `seizeWithMemo`. When `SEIZE` is paused, the function reverts with `ContractPaused(SEIZE)`.

Seize is a transfer, not a burn. The balance moves from `from` to `to` and `totalSupply` remains unchanged. This is the key behavioral difference from `burnBlocked`, which sends to `address(0)` and reduces supply.

**Storage layout change:** A packed `seizePolicyIds` slot is added for `SEIZE_HOLDER_POLICY` and `SEIZE_RECEIVER_POLICY`. This change is additive; `burnBlocked` storage remains unchanged.

### Examples

**Before (old block + burn + mint workaround, still available, deprecated):**

1. Configure `from` as blocked under `TRANSFER_SENDER_POLICY`.
2. Call `burnBlocked(from, amount)` — burns `from`'s balance, gated by `BURN_BLOCKED_ROLE`.
3. Call `mint(treasury, amount)` — separately reissues the same amount, gated by `MINT_ROLE`.
4. Emits: `Transfer(from, address(0), amount)` + `BurnedBlocked(caller, from, amount)` + `Transfer(address(0), treasury, amount)` — two independent operations.

**After (new, single call):**

1. Configure `from` as NOT authorized under `SEIZE_HOLDER_POLICY` (i.e., blocked).
2. Call `seizeWithMemo(from, treasury, amount, memo)` — gated by `SEIZE_ROLE`.
3. Emits, in order:
   - `Transfer(from, treasury, amount)`
   - `Memo(caller, memo)`
   - `Seized(caller, from, treasury, amount)`

## Design Decisions & Alternatives Considered

**Final shipped shape:** `seizeWithMemo` and `burnBlocked` use fully independent policy slots and pause vectors.

- `seizeWithMemo` uses the new `SEIZE_HOLDER_POLICY` (for `from`) and `SEIZE_RECEIVER_POLICY` (for `to`), the new `SEIZE_ROLE`, and the new `PausableFeature.SEIZE`.
- `burnBlocked` retains `TRANSFER_SENDER_POLICY`, `BURN_BLOCKED_ROLE`, and the `BURN` pause vector unchanged.
- Seize operations are rare, so the reserved lane in the transfer packed policy slot was not reused for seize. That lane is kept open for a possible future transfer-side optimization where another hot-path transfer policy could be packed into the existing transfer slot without adding a second `SLOAD`. Because seize is a cold-path/rare-path operation, it instead gets its own packed `seizePolicyIds` slot.

### Function Naming Alternatives

A shared seize-policy approach was rejected: burning and seizing have different effects (see Behavioural Changes), so `burnBlocked` remains independent and no `burnBlockedWithMemo` variant is included.

The name `transferFromBlockedWithMemo` was considered and rejected. `seizeWithMemo` names the intent (seizure) rather than the mechanism (blocked transfer).

## Migration Steps

**Backwards-compatible:** `burnBlocked` continues to work unchanged. No action is required if you do not need seize behavior yet.

**No breaking changes:** All existing selectors, events, and errors remain dialable.

**To adopt `seizeWithMemo`:**

1. Grant `SEIZE_ROLE` to the account(s) that should be able to seize. With no `SEIZE_ROLE` holders, no one can seize.
2. Configure `SEIZE_HOLDER_POLICY` so the accounts you want seizable are NOT authorized under it. With no policy configured (unset = always-allow), no account is seizable.
3. Optionally configure `SEIZE_RECEIVER_POLICY` to restrict where seized funds may land. Unset defaults to always-allow (for example, an unallowlisted treasury still works).

**To reproduce `burnBlocked`'s destroy-supply outcome with seize:** `seizeWithMemo` alone does not reduce `totalSupply`. Seize to a treasury or self address, then call `burn(amount)` from that address if you want the supply destroyed.

**No storage migration:** `burnBlocked`'s storage and behavior are untouched by this change.