# Composite Policies (UNION/INTERSECT)

- **Feature Name**: composite_policy
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Composite Policies (UNION/INTERSECT)

## Summary

This change adds two new `PolicyRegistry` policy types: `UNION` (OR) and `INTERSECT` (AND). These are called "composite policies." A composite policy authorizes an account by combining the results of 2 to 4 existing simple policies. This feature is for users of the policy registry who want to combine several policies without flattening them into one large list. A composite policy can reference only existing simple policies (`ALLOWLIST` or `BLOCKLIST`). A composite policy can never reference another composite policy, and can never reference a built-in sentinel (`ALWAYS_ALLOW` or `ALWAYS_BLOCK`).

This feature ships at the **Cobalt** hardfork. Every mutating call — `createCompositePolicy` and `updateComposite` — is gated by `ActivationRegistry`, the same as every other mutating `PolicyRegistry` function. The feature does not activate automatically. Read-only calls — `isAuthorized`, `compositePolicyChildIds`, `MIN_COMPOSITE_CHILD_POLICIES`, and `MAX_COMPOSITE_CHILD_POLICIES` — remain callable regardless of activation status.

## Motivation

The policy registry currently supports simple boolean policies through `isAuthorized`. Each policy independently returns `true` or `false`. In practice, access control often requires combining multiple policies. For example, an integrator may need to require KYC status *and* pro-user status, or may need to accept either pro-user status *or* lifetime-user status.

Today, the only way to combine policies is for a user to listen for changes on separate allowlists and flatten the results into one list. This duplicates the underlying lists and requires infrastructure to keep the flattened copy in sync.

This change lets a user create a composite policy that references other simple policies directly. A composite policy returns "is authorized" by combining the results of its referenced policies. This design simplifies maintenance: updating one child policy automatically updates every composite policy that references it.

## Background

**B20 Token**

B20 is a token precompile that uses policies to restrict operations such as transfers, minting, and seizing. For each restricted operation, B20 stores a Policy Registry policy ID in a dedicated policy scope. When an operation is attempted, B20 passes the relevant policy ID and account address to the Policy Registry. If the Policy Registry reports that the account is not authorized, B20 rejects the operation.

**Policy Registry**

The Policy Registry is a singleton precompile contract used by B20 tokens. It manages a list of policies. B20 tokens call `isAuthorized(policyId, account)` against a policy ID stored on the relevant policy scope. The Policy Registry is currently used by B20 tokens for the `TRANSFER_FROM`, `TRANSFER_TO`, and `SEIZE_HOLDER` operations.

**Simple policies**

Simple policies are the non-composite policy types: `ALLOWLIST` and `BLOCKLIST`.

- `ALLOWLIST` maintains a list of addresses. It returns authorized `true` if the queried address is in the list, and `false` otherwise.
- `BLOCKLIST` maintains a list of addresses. It returns authorized `false` if the queried address is in the list, and `true` for all other addresses.

## Specs

### Interface Changes

**`PolicyType` enum**

This change adds two new values to the `PolicyType` enum:

```solidity
enum PolicyType {
    BLOCKLIST,
    ALLOWLIST,
    UNION,     // = 2, OR — authorized if any child policy authorizes the account
    INTERSECT  // = 3, AND — authorized only if every child policy authorizes the account
}
```

**New function: `createCompositePolicy`**

```solidity
function createCompositePolicy(address admin, PolicyType policyType, uint64[] calldata childPolicyIds)
    external
    returns (uint64 newPolicyId);
```

`childPolicyIds` must contain between 2 and 4 entries, inclusive. These bounds are exposed as `MIN_COMPOSITE_CHILD_POLICIES` and `MAX_COMPOSITE_CHILD_POLICIES`. Every entry in `childPolicyIds` must be an existing simple policy (`ALLOWLIST` or `BLOCKLIST`). An entry can never be another composite policy, and can never be a built-in sentinel (`ALWAYS_ALLOW` or `ALWAYS_BLOCK`).

The function reverts in this canonical order:

1. `ZeroAddress` — `admin` is the zero address.
2. `IncompatiblePolicyType` — `policyType` is not `UNION` or `INTERSECT`.
3. `ChildPoliciesOutsideOfRange` — the number of entries in `childPolicyIds` is outside `[2, 4]`.
4. `PolicyNotFound` — a child policy does not exist. The function checks this in one pass over the whole set.
5. `InvalidChildPolicy(uint64 childPolicyId)` — a child policy is itself composite or is a built-in sentinel. The function checks this in a second pass over the set.

On success, the function emits, in order:

1. `PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType)`
2. `PolicyAdminUpdated(uint64 indexed policyId, address indexed previousAdmin, address indexed newAdmin)`, with `previousAdmin = address(0)` and `newAdmin = admin`
3. `CompositePolicyUpdated(uint64 indexed policyId, address indexed updater, uint64[] childPolicyIds)`

**New function: `updateComposite`**

```solidity
function updateComposite(uint64 policyId, uint64[] calldata childPolicyIds) external;
```

This function fully replaces the child-policy set of an existing composite policy. The interface provides no partial-update operation and no operation to clear the list. The function applies the same child-validity rules as `createCompositePolicy`: every entry must be an existing simple policy, and the set must contain between 2 and 4 entries.

The function reverts in this canonical order:

1. `PolicyNotFound` — the composite policy referenced by `policyId` does not exist.
2. `IncompatiblePolicyType` — `policyId` refers to a simple policy, not a composite policy.
3. `Unauthorized` — the caller is not the current admin of the composite policy. This check fires before the child-count check.
4. `ChildPoliciesOutsideOfRange` — the number of entries in the new `childPolicyIds` is outside `[2, 4]`.
5. `PolicyNotFound` — a new child policy does not exist.
6. `InvalidChildPolicy(uint64 childPolicyId)` — a new child policy is itself composite or is a built-in sentinel.

On success, the function emits only:

- `CompositePolicyUpdated(uint64 indexed policyId, address indexed updater, uint64[] childPolicyIds)`

The function does not emit `PolicyAdminUpdated`, because `updateComposite` never changes the policy's admin.

**Existing functions: new revert path**

`createPolicy` and `createPolicyWithAccounts` are both already live at Beryl. Starting at Cobalt, both functions also revert with `IncompatiblePolicyType` when `policyType` is `UNION` or `INTERSECT`. This is a previously unreachable revert path, because the `UNION` and `INTERSECT` enum values did not exist before Cobalt.

**Verified errors and events**

The `IPolicyRegistry` interface defines the following errors used by this feature: `ZeroAddress()`, `IncompatiblePolicyType()`, `ChildPoliciesOutsideOfRange()`, `PolicyNotFound()`, `InvalidChildPolicy(uint64 childPolicyId)`, and `Unauthorized()`. It defines the following events used by this feature: `PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType)`, `PolicyAdminUpdated(uint64 indexed policyId, address indexed previousAdmin, address indexed newAdmin)`, and `CompositePolicyUpdated(uint64 indexed policyId, address indexed updater, uint64[] childPolicyIds)`. These signatures were verified against `src/interfaces/IPolicyRegistry.sol`.

### Behavioural Changes

**No B20 code changes required**

A composite policy ID is passed to a B20 policy slot exactly like a simple policy ID. B20 requires zero code changes to support composite policies, because it stores policy slots as an opaque `uint64` and calls `isAuthorized` generically.

**Live, short-circuiting evaluation**

`isAuthorized` on a composite policy evaluates live on every call. It is not a snapshot taken at creation time or at the time of the last `updateComposite` call. On each call, the registry reads each child policy's current membership state.

- `UNION` short-circuits to `true` on the first child that authorizes the account.
- `INTERSECT` short-circuits to `false` on the first child that does not authorize the account.

Recursion never exceeds a depth of 1. Every child is validated to be a simple policy at write time, so a composite policy's children can never themselves be composite policies.

**Child order affects gas, never the outcome**

`UNION` and `INTERSECT` are commutative operations. Reordering `childPolicyIds` never changes whether an account is authorized. Reordering only shifts where the short-circuit lands. To save gas, place the child most likely to short-circuit first: the broadest `ALLOWLIST` for `UNION`, or the tightest `BLOCKLIST` for `INTERSECT`.

**Duplicate child IDs are allowed**

The registry neither sorts nor deduplicates the stored child-policy list. Deduplication would add gas cost to every write, for a set already capped at 4 entries, for little practical benefit. `UNION` and `INTERSECT` are idempotent under duplicate entries, so duplicates do not change the evaluation result.

**Composites cannot shrink below the minimum**

A composite policy can never shrink below 2 children through `updateComposite`. The function enforces the same `[2, 4]` range as `createCompositePolicy`, so there is no path to an empty or undersized composite policy.

**Renounced child policies keep working**

If a child policy's admin renounces administration, the parent composite policy keeps working. `renounceAdmin` only clears the child policy's admin and freezes its future membership changes. The child policy continues to exist, and `isAuthorized` on it continues to resolve normally. The composite policy keeps evaluating that child exactly as before.

**State changes**

- New state: `mapping(uint64 policyId => uint64[] childPolicyIds) children`, at offset 4 within the `base.policy_registry` ERC-7201 namespace. This offset is a namespace offset, not a literal EVM storage slot 4. `[TODO: verify against source — no implementation file with this storage layout was found in this repository]`
- Reused state: one shared global counter, `nextCounter`, shared across simple and composite policies. The counter starts at 2, because `0` and `1` are reserved for the built-in sentinels `ALWAYS_ALLOW` and `ALWAYS_BLOCK`. A composite policy ID encodes its `PolicyType` in the top byte and the next available counter value in the low 56 bits. This is the same encoding scheme used for simple policies, not a separate counter. `[TODO: verify against source — no implementation file with this encoding scheme was found in this repository]`

### Examples

**Before: assigning a simple policy**

An integrator assigns one existing policy directly to a B20 policy scope:

```solidity
b20.updatePolicy(TRANSFER_SENDER_POLICY, allowlistPolicyId);
```

Only accounts in `allowlistPolicyId` can transfer.

**After: creating and assigning a composite policy**

Assume two existing simple policies: `employeesPolicyId` (`ALLOWLIST`) and `approvedRegionPolicyId` (`ALLOWLIST`).

Create a `UNION` composite policy:

```solidity
policyRegistry.createCompositePolicy(admin, UNION, [employeesPolicyId, approvedRegionPolicyId]);
```

This call emits, in order:

- `PolicyCreated(policyId, admin, UNION)`
- `PolicyAdminUpdated(policyId, address(0), admin)`
- `CompositePolicyUpdated(policyId, admin, [employeesPolicyId, approvedRegionPolicyId])`

Assign the new composite policy to B20:

```solidity
b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId);
```

B20 requires no composite-specific logic. It passes the policy ID to the registry exactly as it would for a simple policy.

**Updating a composite policy**

```solidity
policyRegistry.updateComposite(compositePolicyId, [employeesPolicyId, trustedPartnersPolicyId]);
```

This call emits:

- `CompositePolicyUpdated(policyId, admin, [employeesPolicyId, trustedPartnersPolicyId])`

B20 continues using the same policy ID. No token-side update is required. Because evaluation is live, future authorization checks use the new child set immediately — the registry does not take a snapshot.

## Design Decisions & Alternatives Considered

**Decision**: Provide two explicit policy types, `UNION` and `INTERSECT`, with a single creation function, `createCompositePolicy`, and a full-replacement update function, `updateComposite`.

**Alternative 1: One generic `COMPOSITE` type**

This alternative would store a separate operator (`AND`, `OR`, `NOT`, `XOR`) in composite storage. It was rejected because it requires storing both a "composite" flag and the operator, and adds either extra storage reads or a more complicated ID-encoding scheme. It also adds unnecessary complexity before there is any requirement for `NOT`, `XOR`, or nested expressions. A generic boolean-expression design creates a larger gas and audit surface than the chosen approach.

**Alternative 2: Token-level policy groups**

This alternative would keep the Policy Registry unchanged, and instead have each B20 token store multiple policy IDs plus an operator. It was rejected because composite policies would not be reusable entities under this design. It requires changes across B20, its token variants, factories, and token hot paths. It does not support sharing one composite policy across multiple tokens, and it spreads complexity across more contracts than the chosen approach.

**Alternative 3: Incremental child updates**

This alternative would provide `addCompositeOperand` and `removeCompositeOperand` functions instead of full-set replacement. It was rejected because the child list is capped at 4 entries, so the benefit of incremental mutation is limited. Dynamic-array mutation requires swap/remove logic, length tracking, and deduplication logic. Full replacement is simpler and atomic, and a caller can resend the complete list at low cost.

**Alternative 4: Separate creator functions**

This alternative would use `createUnionPolicy` and `createIntersectPolicy` instead of one function that takes a `policyType` argument. It was rejected because it doubles the creation API surface. A single `createCompositePolicy` function keeps policy creation consistent with the existing `createPolicy` pattern. Adding future operators under the separate-function design would require additional functions for each new operator.

## Migration Steps

This change is backwards-compatible. Existing simple policies (`ALLOWLIST` and `BLOCKLIST`) continue to work unchanged. No action is required if you do not need composite behavior.

For users currently flattening multiple lists into one policy, follow these steps:

1. Identify the simple policies you want to combine.
2. Call `policyRegistry.createCompositePolicy(admin, UNION or INTERSECT, [childPolicyIds])`.
3. Update the B20 token's policy scope to point to the new composite policy ID:
   ```solidity
   b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId);
   ```
   No B20 contract change is required. B20 treats the composite policy ID as an opaque `uint64`, exactly like a simple policy ID.
4. Remove the old flattened policy if it is no longer needed.

There are no breaking changes. All existing selectors, events, and errors remain dialable at Cobalt.

There is no storage migration required. The `children` mapping is a new, empty mapping at ERC-7201 offset 4. Cobalt activation does not modify existing `PolicyRegistry` state at offsets 0–3.
