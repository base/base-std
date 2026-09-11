# Denim: Preauthorized Spenders

- **Feature Name**: preauthorized_spender
- **Start Date**: 2026-09-11
- **Title**: Issuer-controlled infinite allowances through `PREAUTHORIZED_SPENDER_ROLE`

## Summary

Denim lets a B20 issuer grant an account permission to spend from every holder without holder approvals.

## Motivation

Some token integrations need one contract, such as a router or settlement system, to spend from every holder. For example, an issuer can preauthorize Permit2 to unlock signature-based transfers. This provides a workaround when a smart contract account cannot use token-native permit functionality and removes the per-holder approval transaction.

## Specs

### Interface changes

`PREAUTHORIZED_SPENDER_ROLE()` is added to the shared [`IB20`](../src/interfaces/IB20.sol) interface.

| Function | Selector | Denim change |
| --- | --- | --- |
| `PREAUTHORIZED_SPENDER_ROLE()` | `0x6c0f8b76` | New shared role getter on Asset and Stablecoin. |
| `allowance(address,address)` | `0xdd62ed3e` | Returns `type(uint256).max` when `spender` holds `PREAUTHORIZED_SPENDER_ROLE`. |
| `transferFrom(address,address,uint256)` | `0x23b872dd` | Skips allowance validation and consumption when the caller holds `PREAUTHORIZED_SPENDER_ROLE`. |
| `transferFromWithMemo(address,address,uint256,bytes32)` | `0x929c2539` | Applies the same preauthorized spender behavior as `transferFrom`. |

The role value is:

```solidity
keccak256("PREAUTHORIZED_SPENDER_ROLE")
// 0xb90b441c392e1b39b562e08d16a15eab44f161ced0b6366c03aa7d09a22f1a41
```

No new mutator, event, error, or storage slot is added. Issuers manage membership with `grantRole`, `revokeRole`, and `renounceRole`. `getRoleAdmin(PREAUTHORIZED_SPENDER_ROLE)` defaults to `DEFAULT_ADMIN_ROLE` and remains delegable through `setRoleAdmin`.

### Behavioral changes

For a caller that holds `PREAUTHORIZED_SPENDER_ROLE`:

- `allowance(owner, caller)` returns `type(uint256).max` for every `owner`.
- `transferFrom` and `transferFromWithMemo` do not read or decrement the stored allowance.
- A finite stored allowance remains unchanged and becomes visible again if the role is revoked.
- `approve(caller, 0)` does not opt the holder out.
- `TRANSFER_EXECUTOR_POLICY`, `TRANSFER_SENDER_POLICY`, and `TRANSFER_RECEIVER_POLICY` still run.
- The `TRANSFER` pause vector and balance checks still run.

For any other caller, allowance behavior remains unchanged. A finite allowance decrements by the transferred amount, and `type(uint256).max` remains the non-decrementing ERC-20 sentinel.

### Storage layout

There is no storage change. Preauthorized spender membership uses the existing role mapping. Holder allowances remain in their existing slots while the spender holds `PREAUTHORIZED_SPENDER_ROLE`.

### Gas considerations

- `allowance` adds a role-membership read. A preauthorized spender returns after that read and skips the stored allowance read.
- `transferFrom` and `transferFromWithMemo` add a role-membership read for all callers.
- A preauthorized spender skips the allowance read and any finite-allowance write.
- A caller without the role pays for the additional role read and then follows the existing allowance path.
- Exact native gas costs depend on the B20 logic v3 implementation and must be benchmarked with that implementation.

## Example

```solidity
bytes32 spenderRole = token.PREAUTHORIZED_SPENDER_ROLE();
token.grantRole(spenderRole, address(permit2));

// Returns type(uint256).max even when alice never approved Permit2.
uint256 effectiveAllowance = token.allowance(alice, address(permit2));

// Permit2 can execute signature-based transfers against alice's token balance.
```

## Design Decisions and Alternatives Considered

### Selected design

- Add a dedicated role to keep holder-spending authority separate from Asset operations.
- Reuse the existing RBAC set instead of adding a spender registry or policy scope.
- Keep the set empty by default. No address, including Permit2, receives implicit authority.
- Grant infinite authority only. Per-spender caps are not supported.
- Do not add holder opt-out state. Issuer role revocation is the removal path.
- Reuse `DEFAULT_ADMIN_ROLE` as the default role administrator.
- Waive only allowance checks. Compliance policies and pause remain independent controls.

### Alternatives considered

| Alternative | Reason not selected |
| --- | --- |
| Dedicated spender mapping with `isAuthorizedSpender`, `setAuthorizedSpender`, and a new event | Adds storage, mutators, and an event when the existing RBAC set already provides membership management. |
| New Policy Registry scope | An unset policy ID means always allow. Special-casing that default for spender grants would invert existing policy semantics and create a severe configuration risk. |
| Explicit token API backed by a Policy Registry policy | Requires both a token-level policy reference and registry configuration, which adds two moving parts for one permission. |
| Reuse the Asset `OPERATOR_ROLE` | Combines holder-spending authority with announcements and multiplier administration. A separate role keeps each capability explicit. |
| Fixed Permit2 authorization | Restricts issuers to one integration. The selected design supports Permit2 and other issuer-chosen spenders without granting any address by default. |
| Per-holder opt-out | Adds per-holder state and another transfer branch without changing the issuer trust model. Role revocation remains the authority-removal path. |
| Dedicated admin role or delayed grants | Adds administration and pending-grant state. The existing delegable role-admin model supports separation when an issuer needs it, while keeping grants and revocations immediate. |

## Migration Steps

### Issuers

1. Check for any historical generic grant of the `PREAUTHORIZED_SPENDER_ROLE` hash.
2. Check `getRoleAdmin(PREAUTHORIZED_SPENDER_ROLE)` if the role hash was already configured.
3. Grant the role only to contracts and accounts that may move every holder's balance.

### Integrators

1. Do not assume that `allowance == type(uint256).max` came from holder approval.
2. Do not present `approve(spender, 0)` as a revocation path for role-based authority.
3. Continue to handle `ContractPaused`, `PolicyForbids`, and `InsufficientBalance` on preauthorized spender transfers.

Both variants gain the additive `PREAUTHORIZED_SPENDER_ROLE()` selector. The existing ERC-20 selectors change behavior only for accounts that hold the new role hash.
