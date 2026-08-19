# Seize Surface + `burnBlocked` Deprecation

- **Feature Name**: seize
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Seize surface + burnBlocked deprecation

## Summary

This change adds `seizeWithMemo` to the shared `IB20` interface (inherited by both B20 Asset and B20 Stablecoin). The Cobalt hardfork activates this feature. Read calls against `IB20` are callable regardless of activation status; the `seizeWithMemo` write path is gated by `ActivationRegistry` and will revert with `Unauthorized` if Cobalt is not active.

The original workflow to seize an asset required three steps: block the sender under `TRANSFER_SENDER_POLICY`, call `burnBlocked` (which burns supply), then call `mint` to reissue to the seizure account. `seizeWithMemo` replaces this with a single administrative call that reassigns the balance directly from `from` to `to`. Total supply is unchanged.

`burnBlocked` remains callable but is now **deprecated-dialable**. Its behavior, selector (`0xec0cf3dc`), error (`AccountNotBlocked`), and event (`BurnedBlocked`) are unchanged. No removal date is committed.

**Compatibility promise**: all existing selectors, events, and errors remain dialable. No breaking changes.

## Mapping Table

| Old symbol | New symbol | Status | Reason |
|------------|------------|--------|--------|
| — | `seizeWithMemo(address,address,uint256,bytes32)` | new | Single-call admin seize; selector `0xf916d81b` |
| — | `SEIZE_ROLE()` | new | Role constant; selector `0x3c7e9ba5` |
| — | `SEIZE_HOLDER_POLICY()` | new | Policy scope; selector `0xb279d311` — gates who is seizable (inverted membership) |
| — | `SEIZE_RECEIVER_POLICY()` | new | Policy scope; selector `0xb31da27f` — gates seizure destination |
| — | `event Seized(address,address,address,uint256)` | new | Emitted after `Transfer` + `Memo`; topic0 `0xa9aec5d8b86e2fa2fd6ac3af62f2622e3dfdab1967d4cbbb56a5df7d74cb887c` |
| — | `error AccountNotSeizable(address)` | new | Selector `0x91dbbc8d` |
| — | `PausableFeature.SEIZE` | new | Dedicated pause vector, independent of `BURN` |
| `burnBlocked(address,uint256)` | `burnBlocked(address,uint256)` | deprecated-dialable | Unchanged; retains `BURN_BLOCKED_ROLE`, `TRANSFER_SENDER_POLICY`, `BURN` pause vector |

## New at Cobalt (adopt these)

### `seizeWithMemo`

```solidity
function seizeWithMemo(address from, address to, uint256 amount, bytes32 memo) external;
```

**Caller**: must hold `SEIZE_ROLE`.  
**Policies checked** (in order):
1. `SEIZE_HOLDER_POLICY` — `from` must be **not authorized** (inverted membership). Reverts `AccountNotSeizable` if authorized.
2. `SEIZE_RECEIVER_POLICY` — `to` must be authorized. Reverts `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)` if not. Unset slot defaults to always-allow.

**Policies NOT checked**: `TRANSFER_SENDER_POLICY`, `TRANSFER_RECEIVER_POLICY`, `TRANSFER_EXECUTOR_POLICY`, and allowance.

**Events emitted** (in order):
1. `Transfer(from, to, amount)`
2. `Memo(caller, memo)`
3. `Seized(caller, from, to, amount)`

**Reverts** (canonical order):
- `ContractPaused(SEIZE)` — if `SEIZE` is paused
- `AccessControlUnauthorizedAccount` — if caller lacks `SEIZE_ROLE`
- `InvalidReceiver` — if `to == address(0)` or `from == to`
- `InvalidSender` — if `from == address(0)`
- `AccountNotSeizable` — if `from` authorized under `SEIZE_HOLDER_POLICY`
- `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)` — if `to` not authorized
- `InsufficientBalance` — if `from` balance < `amount`

### Pause vector

`PausableFeature.SEIZE` is a dedicated pause vector. It is independent of `BURN` (which gates `burnBlocked`, `burn`, `burnWithMemo`). Call `pause([SEIZE])` / `unpause([SEIZE])` with `PAUSE_ROLE` / `UNPAUSE_ROLE`.

### Policy scopes

- `SEIZE_HOLDER_POLICY` — evaluated against `from`. Inverted: `from` is seizable **only when NOT authorized**. Unset = always-allow → no account is seizable until configured.
- `SEIZE_RECEIVER_POLICY` — evaluated against `to`. Standard: `to` must be authorized. Unset = always-allow → treasury need not be allowlisted.

These two policy IDs are packed into a new `seizePolicyIds` storage slot (additive; `burnBlocked` storage unchanged).

### `burnBlocked` (deprecated but supported)

```solidity
function burnBlocked(address from, uint256 amount) external;
```

Retained for back-compat. Continues to:
- Gate by `BURN_BLOCKED_ROLE` and `BURN` pause vector (not `SEIZE`)
- Read `TRANSFER_SENDER_POLICY` for blocked check (distinct from `SEIZE_HOLDER_POLICY`)
- Emit `Transfer(from, address(0), amount)` + `BurnedBlocked(caller, from, amount)`
- Reduce `totalSupply`

**Prefer**: `seizeWithMemo(from, treasury, amount, memo)` followed by `burn(amount)` from `treasury` if you want supply destroyed.

## Guarantees & Edge Cases

**Q: Does `seizeWithMemo` affect `totalSupply`?**  
No. It is a transfer, not a burn. Balance moves `from` → `to`; `totalSupply` unchanged.

**Q: Can I seize from an account that is not blocked under `TRANSFER_SENDER_POLICY`?**  
Yes. `seizeWithMemo` uses `SEIZE_HOLDER_POLICY`, which is completely independent. An account can be seizable even if it is not blocked for transfers.

**Q: What happens if `SEIZE_RECEIVER_POLICY` is unset?**  
Defaults to always-allow. Seizure can send to any destination (e.g., an unallowlisted treasury).

**Q: What if `SEIZE_HOLDER_POLICY` is unset?**  
Unset = always-allow. Under inverted membership, this means **no account is seizable** until the policy is configured. This is intentional: seizure is opt-in.

**Q: Does `seizeWithMemo` check `transferFrom` allowance?**  
No. It is an admin operation that skips all transfer-side policies and allowance.

**Q: Can I call `seizeWithMemo` if Cobalt is not active?**  
No. The write path is gated by `ActivationRegistry`. The call reverts `Unauthorized` until Cobalt activates. Read-only calls (e.g., `SEIZE_ROLE()`, `SEIZE_HOLDER_POLICY()`) work regardless.

**Q: Is there a `burnBlockedWithMemo` variant?**  
No. The shared seize-policy approach was rejected because burning and seizing have different effects: `burnBlocked` destroys supply, `seizeWithMemo` reassigns balances.

**Q: What if I want the old `burnBlocked` + `mint` supply-destroying behavior?**  
Call `seizeWithMemo(from, treasury, amount, memo)` then `burn(amount)` from `treasury`. This is two calls instead of the old three, and the `Seized` event ties the two operations together.

**Q: Any storage migration?**  
No. The new `seizePolicyIds` slot is additive. `burnBlocked` storage is untouched.

## Migration Steps

1. **No action required** if you don't need seize behavior yet. `burnBlocked` works unchanged.
2. **To adopt `seizeWithMemo`**:
   a. Grant `SEIZE_ROLE` to the account(s) that should seize. With no holders, no one can seize.
   b. Configure `SEIZE_HOLDER_POLICY` so the accounts you want seizable are **NOT authorized**. With no policy configured (unset = always-allow), no account is seizable.
   c. Optionally configure `SEIZE_RECEIVER_POLICY` to restrict where seized funds may land. Unset defaults to always-allow.
3. **To reproduce `burnBlocked`'s destroy-supply outcome**: `seizeWithMemo(from, treasury, amount, memo)` then `burn(amount)` from `treasury`.

All existing selectors, events, and errors remain dialable. No breaking changes. No storage migration.