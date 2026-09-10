# Denim: Issuer-Approved Operators

- **Feature Name**: operator_allowance
- **Start Date**: 2026-09-10
- **Title**: Issuer-approved infinite allowances through `OPERATOR_ROLE`

## Summary

Denim lets a B20 issuer grant an account permission to spend from every holder without holder approvals. The issuer uses the existing role system. Denim adds no implicit grants; any existing or future grant of the `OPERATOR_ROLE` hash receives this authority.

## Motivation

Some token integrations need one contract, such as a router or settlement system, to spend from every holder. Requiring each holder to call `approve` adds a transaction and prevents the integration from working for holders that cannot make an approval call.

## Specs

### Interface changes

`OPERATOR_ROLE()` moves to the shared [`IB20`](../src/interfaces/IB20.sol) interface.

| Function | Selector | Denim change |
| --- | --- | --- |
| `OPERATOR_ROLE()` | `0xf5b541a6` | Already available on Asset; newly available on Stablecoin through `IB20`. |
| `allowance(address,address)` | `0xdd62ed3e` | Returns `type(uint256).max` when `spender` holds `OPERATOR_ROLE`. |
| `transferFrom(address,address,uint256)` | `0x23b872dd` | Skips allowance validation and consumption when the caller holds `OPERATOR_ROLE`. |
| `transferFromWithMemo(address,address,uint256,bytes32)` | `0x929c2539` | Applies the same operator behavior as `transferFrom`. |

The role value remains:

```solidity
keccak256("OPERATOR_ROLE")
// 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929
```

No new mutator, event, error, or storage slot is added. Issuers manage membership with `grantRole`, `revokeRole`, and `renounceRole`. `getRoleAdmin(OPERATOR_ROLE)` defaults to `DEFAULT_ADMIN_ROLE` and remains delegable through `setRoleAdmin`.

### Behavioral changes

For a caller that holds `OPERATOR_ROLE`:

- `allowance(owner, caller)` returns `type(uint256).max` for every `owner`.
- `transferFrom` and `transferFromWithMemo` do not read or decrement the stored allowance.
- A finite stored allowance remains unchanged and becomes visible again if the role is revoked.
- `approve(caller, 0)` does not opt the holder out.
- `TRANSFER_EXECUTOR_POLICY`, `TRANSFER_SENDER_POLICY`, and `TRANSFER_RECEIVER_POLICY` still run.
- The `TRANSFER` pause vector and balance checks still run.

For any other caller, allowance behavior remains unchanged. A finite allowance decrements by the transferred amount, and `type(uint256).max` remains the non-decrementing ERC-20 sentinel.

### Storage layout

There is no storage change. Operator membership uses the existing role mapping. Holder allowances remain in their existing slots, including while the spender holds `OPERATOR_ROLE`.

## Example

```solidity
bytes32 operatorRole = token.OPERATOR_ROLE();
token.grantRole(operatorRole, address(router));

// Returns type(uint256).max even when alice never approved the router.
uint256 effectiveAllowance = token.allowance(alice, address(router));

// The router calls token.transferFrom(alice, recipient, amount)
// from its own execution context.
```

## Design Decisions

- Reuse the existing RBAC set instead of adding an operator registry or policy scope.
- Keep the set empty by default. No address, including Permit2, receives implicit authority.
- Grant infinite authority only. Per-operator caps are not supported.
- Do not add holder opt-out state. Issuer role revocation is the removal path.
- Reuse `DEFAULT_ADMIN_ROLE` as the default role administrator.
- Waive only allowance checks. Compliance policies and pause remain independent controls.

## Migration Steps

### Issuers

1. Enumerate historical `RoleGranted` and `RoleRevoked` events for `OPERATOR_ROLE`.
2. Revoke Asset operators that must not gain holder-spending authority before Denim activates.
3. Check Stablecoin tokens for generic grants of the same role hash, even though the getter was not previously on the Stablecoin interface.
4. Check `getRoleAdmin(OPERATOR_ROLE)` because an earlier `setRoleAdmin` call may have delegated role administration.
5. Grant the role only to contracts and accounts that may move every holder's balance.

### Integrators

1. Do not assume that `allowance == type(uint256).max` came from holder approval.
2. Do not present `approve(operator, 0)` as a revocation path for role-based authority.
3. Continue to handle `ContractPaused`, `PolicyForbids`, and `InsufficientBalance` on operator transfers.

This change is ABI-compatible for Asset but behaviorally breaking for existing operator assignments. Stablecoin gains the additive `OPERATOR_ROLE()` selector and the same behavioral change on existing ERC-20 selectors.
