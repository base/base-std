# Composite Policies (UNION/INTERSECT)

- **Feature Name**: composite_policy
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Composite Policies (UNION/INTERSECT)

## Summary

Asset issuers often use the Policy Registry to maintain compliance lists. They and other Policy Registry users can also depend on shared lists maintained by other policy owners. This feature lets them compose these policies without copying entries into a new list or maintaining infrastructure to synchronize updates.

The feature introduces two new `PolicyRegistry` policy types: `UNION` (OR) and `INTERSECT` (AND), collectively called composite policies. A `UNION` policy authorizes an account if any child policy authorizes it. An `INTERSECT` policy authorizes an account only if every child policy authorizes it. Each composite references two to four existing simple policies (`ALLOWLIST` or `BLOCKLIST`). Composite policies cannot reference other composites, and the registry enforces this constraint when a composite is created or updated. Authorization uses each child's current state, so updating a child automatically affects every composite that references it.

## Motivation

Asset issuance platforms often manage many assets that share authorization requirements. An issuer can reuse one policy across these assets, but assigning that policy directly leaves no way to customize authorization for an individual asset. A composite policy lets the issuer use shared policies by default while preserving per-asset overrides. For example, a `UNION` can combine a shared allowlist with a token-specific allowlist.

Without composition, users must copy entries from source policies into a new, flattened policy and operate infrastructure that monitors and synchronizes every source update. This approach duplicates policy data and can leave the copy stale when synchronization is delayed or fails. Until the copy catches up, valid transfers can be rejected or transfers that the source policy no longer authorizes can proceed.

Access control can also require more than one condition. An application might require both KYC verification and ProUser status, or accept either ProUser status or LifetimeUser status. Composite policies support these cases by introducing `UNION` (OR) and `INTERSECT` (AND). Because authorization evaluates each child policy's current state, one child update immediately applies to every composite that references it, without list-copying infrastructure.

## Background

### B20 Token

B20 is a token precompile that uses policies to restrict operations such as transfers, minting, and seizing. For each restricted operation, B20 stores a Policy Registry policy ID in a dedicated policy scope. When an operation is attempted, B20 passes the relevant policy ID and account address to the Policy Registry. If the account is not authorized, B20 rejects the operation.

### Policy Registry

The Policy Registry is a singleton precompile contract used by B20 tokens. It manages a list of policies; B20 tokens call `isAuthorized(policyId, account)` against a policy ID stored on the relevant policy scope. Currently, B20 tokens use the Policy Registry for `TRANSFER_FROM`, `TRANSFER_TO`, and `SEIZE_HOLDER`.

#### Simple Policies

Simple policies are the non-composite policy types: `ALLOWLIST` and `BLOCKLIST`.

- `ALLOWLIST` has a list of addresses. It returns authorized `true` if the address is in the list, `false` otherwise.
- `BLOCKLIST` has a list of addresses. It returns authorized `false` if the address is in the list, `true` for all other addresses.

## Specs

### Interface Changes

The relevant `IPolicyRegistry` interface changes are:

```solidity
enum PolicyType {
    BLOCKLIST,
    ALLOWLIST,
    UNION,
    INTERSECT
}

error ChildPoliciesOutsideOfRange();
error InvalidChildPolicy(uint64 childPolicyId);

event CompositePolicyUpdated(uint64 indexed policyId, address indexed updater, uint64[] childPolicyIds);

function createCompositePolicy(address admin, PolicyType policyType, uint64[] calldata childPolicyIds)
    external
    returns (uint64 newPolicyId);

function updateComposite(uint64 policyId, uint64[] calldata childPolicyIds) external;

function compositePolicyChildIds(uint64 policyId) external view returns (uint64[] memory);

function MIN_COMPOSITE_CHILD_POLICIES() external view returns (uint256);
function MAX_COMPOSITE_CHILD_POLICIES() external view returns (uint256);
```

| Symbol | Selector / Topic0 | Status | Notes |
|--------|-------------------|--------|-------|
| `createCompositePolicy(address,uint8,uint64[])` | `0x6fdd1491` | NEW | `PolicyType` ABI-encodes as `uint8`; creates a UNION/INTERSECT composite |
| `updateComposite(uint64,uint64[])` | `0xbfe142c0` | NEW | Full replacement of the child set |
| `compositePolicyChildIds(uint64)` | `0x7c40df74` | NEW (view) | Returns the stored child set verbatim; empty for non-composites |
| `MIN_COMPOSITE_CHILD_POLICIES()` | `0xb3ae29f7` | NEW (view) | Returns `2` |
| `MAX_COMPOSITE_CHILD_POLICIES()` | `0x54309870` | NEW (view) | Returns `4` |
| `ChildPoliciesOutsideOfRange()` | `0x697ec868` | NEW (error) | Child count not in `[2, 4]`; distinct from `BatchSizeTooLarge` (64-account cap) |
| `InvalidChildPolicy(uint64)` | `0x46508ef6` | NEW (error) | Child is itself a composite or a built-in sentinel |
| `CompositePolicyUpdated(uint64,address,uint64[])` | `0x4ff6adaab31b0df87aa7b8b7320c52b8b3b5eede3bf28a6baaaa8b8b7e1d6363` | NEW (event) | Topic0; emitted on composite create and every update; carries full post-update set |
| `isAuthorized(uint64,address)` | (unchanged) | extended | Now dispatches composites (live child evaluation); signature unchanged |
| `createPolicy(address,uint8)` | `0xca5d55f6` | extended | Now rejects `UNION`/`INTERSECT` with `IncompatiblePolicyType` (see below) |
| `createPolicyWithAccounts(address,uint8,address[])` | `0xa2d3044f` | extended | Same new `IncompatiblePolicyType` rejection |

The `PolicyType` enum introduces two new values:
- `UNION = 2` — authorized if any child policy authorizes the account (OR)
- `INTERSECT = 3` — authorized only if every child policy authorizes the account (AND)

#### `createCompositePolicy(admin, policyType, childPolicyIds)`

- `childPolicyIds` must contain at least `MIN_COMPOSITE_CHILD_POLICIES` (`2`) and no more than `MAX_COMPOSITE_CHILD_POLICIES` (`4`).
- The `isAuthorized` gas cost increases with each child policy evaluated because each child requires a membership storage read. The highest cost occurs when all four children are evaluated.
- Each child must be an existing `ALLOWLIST` or `BLOCKLIST` policy. Composite policies and the built-in `ALWAYS_ALLOW` and `ALWAYS_BLOCK` policies are not valid children.

The canonical revert order is:
1. `ZeroAddress` (admin)
2. `IncompatiblePolicyType` (policyType not UNION/INTERSECT)
3. `ChildPoliciesOutsideOfRange` (count not in `[2, 4]`)
4. `PolicyNotFound` (a child doesn't exist, checked as one pass over the whole set)
5. `InvalidChildPolicy` (a child is itself composite or sentinel, checked as a second pass)

The function emits, in order:
- `PolicyCreated(policyId, creator, policyType)`
- `PolicyAdminUpdated(policyId, address(0), admin)`
- `CompositePolicyUpdated(policyId, creator, childPolicyIds)`

#### `updateComposite(policyId, childPolicyIds)`

This function replaces the entire child set with two to four existing simple policies, subject to the same validation rules as `createCompositePolicy`. It does not support partial updates or an empty child set.

The canonical revert order is:
1. `PolicyNotFound` (composite itself doesn't exist)
2. `IncompatiblePolicyType` (`policyId` is a simple policy)
3. `Unauthorized` (caller isn't the current admin — fires before the count check)
4. `ChildPoliciesOutsideOfRange`
5. `PolicyNotFound` (a new child doesn't exist)
6. `InvalidChildPolicy`

The function emits only `CompositePolicyUpdated(policyId, updater, childPolicyIds)` — no `PolicyAdminUpdated`, since the admin does not change.

### Behavioural Changes

#### Existing Functions with Changed Revert Behavior

`createPolicy` and `createPolicyWithAccounts` revert with `IncompatiblePolicyType` when creating a `UNION` or `INTERSECT` policy.

#### Authorization Implementation

`isAuthorized` uses the same result from each child, whether that child is an `ALLOWLIST` or a `BLOCKLIST`.
The composite only determines how to combine those results:

```text
isAuthorized(policyId, account):
    if policy is ALLOWLIST:
        return account is in the policy

    if policy is BLOCKLIST:
        return account is not in the policy

    if policy is UNION:
        for each child policy:
            if isAuthorized(child, account):
                return true
        return false

    if policy is INTERSECT:
        for each child policy:
            if not isAuthorized(child, account):
                return false
        return true
```

#### Notes

- Evaluation is live, not a snapshot. Each call reads the current membership of each evaluated child.
- Evaluation short-circuits. `UNION` stops at the first authorizing child, and `INTERSECT` stops at the first
  non-authorizing child.
- Gas cost depends on the number of child policies evaluated. Child order can therefore affect gas, but it
  cannot affect the authorization result. Put the child most likely to short-circuit first.
- `ALLOWLIST` and `BLOCKLIST` children use the same composite evaluation path. Each child first resolves its
  own authorization result, and then the composite combines those results.
- Composite children must be simple policies, so recursion cannot exceed one level.
- Duplicate child IDs are allowed. The registry preserves their order and does not deduplicate them.
- `updateComposite` requires two to four children, so an existing composite cannot become empty or undersized.
- A child remains effective if its admin renounces. Renouncing freezes future membership changes but does not
  delete the child or change its current authorization results.
- A well-formed but never-created `UNION` ID has no children and returns `false`. A well-formed but never-created
  `INTERSECT` ID has no children and returns `true`. Consumers that store policy IDs MUST call
  `policyExists(policyId)` before storing them; otherwise, an invalid `INTERSECT` ID behaves like `ALWAYS_ALLOW`.

#### State Changes

**Storage layout change:** A `children` mapping is added at offset 4 in the `base.policy_registry` ERC-7201
namespace. The change is additive. Existing state at offsets 0–3 is unchanged, and no storage migration is
needed. Offset 4 is relative to the namespace location, not literal EVM slot 4.

- Namespace location: `0x00503aeb06982fa1fe3151dc68f90b3946c55c449dfd447e49dcaece71ba4a00`
- Placed at `CHILDREN_OFFSET = 4`
- Field type: `mapping(uint64 policyId => uint64[] childPolicyIds) children`

For each `policyId`, the mapping entry stores the dynamic array length. Array elements start at the hash of that
entry and pack four `uint64` child policy IDs into each 256-bit slot. The two-to-four-child limit means each
composite uses one element slot.

| Bits    | Array index | Field                  |
| ------- | ----------- | ---------------------- |
| 0–63    | 0           | `childPolicyIds[0]`    |
| 64–127  | 1           | `childPolicyIds[1]`    |
| 128–191 | 2           | `childPolicyIds[2]`    |
| 192–255 | 3           | `childPolicyIds[3]`    |

**Reused state:** Simple and composite policies share the global `nextCounter`. The counter starts at 2 because
`0` and `1` are reserved for `ALWAYS_ALLOW` and `ALWAYS_BLOCK`. A composite policy ID encodes `PolicyType` in
the top byte and the next available counter value in the low 56 bits. This is the same encoding scheme that
simple policies use; composite policies do not use a separate counter.

### Examples

#### Before (Simple Policy)

Assign one existing policy directly to a B20 policy scope:

```solidity
b20.updatePolicy(TRANSFER_SENDER_POLICY, allowlistPolicyId)
```

Only accounts in `allowlistPolicyId` can transfer.

#### After (Composite Policy)

Assume existing simple policies: `employeesPolicyId` (ALLOWLIST), `approvedRegionPolicyId` (ALLOWLIST).

Create a UNION composite:

```solidity
policyRegistry.createCompositePolicy(admin, UNION, [employeesPolicyId, approvedRegionPolicyId])
```

Emits: `PolicyCreated(policyId, admin, UNION)` + `PolicyAdminUpdated(policyId, 0, admin)` + `CompositePolicyUpdated(policyId, admin, [children])`.

Assign to B20:

```solidity
b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId)
```

B20 has no composite-specific logic — it passes the policy ID to the registry as usual.

#### Updating a Composite

```solidity
policyRegistry.updateComposite(compositePolicyId, [employeesPolicyId, trustedPartnersPolicyId])
```

Emits: `CompositePolicyUpdated(policyId, admin, [newChildren])`.

B20 continues using the same policy ID — no token-side update required.

Future authorization checks use the new child set immediately (live evaluation, no snapshot).

## Design Decisions & Alternatives Considered

**Decision**: Two explicit policy types (`UNION`, `INTERSECT`) with a single `createCompositePolicy` function and full-replacement `updateComposite`.

**Alternative 1: One generic COMPOSITE type**
- Store a separate operator (AND, OR, NOT, XOR) in composite storage.
- Rejected because:
  - Requires storing both "composite" flag and the operator.
  - Adds storage reads or more complicated ID encoding.
  - Unnecessary complexity before there is a requirement for NOT, XOR, or nested expressions.
  - Generic boolean expressions create a larger gas and audit surface.

**Alternative 2: Token-level policy groups**
- Keep Policy Registry unchanged; have each B20 token store multiple policy IDs + an operator.
- Rejected because:
  - Composite policies would not be reusable entities.
  - Requires changes across B20, token variants, factories, and token hot paths.
  - Does not support sharing one composite policy across multiple tokens.
  - Spreads complexity across more contracts.

**Alternative 3: Incremental child updates**
- Provide `addCompositeOperand` / `removeCompositeOperand` functions.
- Rejected because:
  - Child list is capped at 4 entries.
  - Dynamic-array mutation requires swap/remove, length, and deduplication logic.
  - Full replacement is simpler and atomic.
  - Caller can resend the complete list at low cost.

**Alternative 4: Separate creator functions**
- Use `createUnionPolicy` and `createIntersectPolicy`.
- Rejected because:
  - Doubles the creation API surface.
  - A single `createCompositePolicy` keeps policy creation consistent.
  - Future operators would require additional functions.

**Alternative 5: Nested composites (a composite referencing another composite)**
- Allow composite children, to some bounded depth, instead of restricting children to simple `ALLOWLIST`/`BLOCKLIST` policies.
- Rejected because:
  - Restricting children to simple policies guarantees `isAuthorized` recursion terminates at depth 1 — no cycle risk, no unbounded traversal.
  - Bounds worst-case gas and the audit surface of authorization evaluation.
  - No demonstrated need for nested expressions; a wrapper composite can be introduced later if one ever arises.

## Migration Steps

**Backwards-compatible**: Existing simple policies (`ALLOWLIST`/`BLOCKLIST`) continue to work unchanged. No action required if you do not need composite behavior.

**For users currently flattening multiple lists into one policy**:
  1. Identify the simple policies you want to combine.
  2. Call `policyRegistry.createCompositePolicy(admin, UNION or INTERSECT, [childPolicyIds])`.
  3. Update the B20 token's policy scope to point to the new composite policy ID:
     - `b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId)`
     - No B20 contract change is required — B20 treats the composite ID as an opaque `uint64` exactly like a simple policy ID.
  4. Remove the old flattened policy if no longer needed.

**No breaking changes**: All existing selectors, events, and errors remain dialable at Cobalt.

**No storage migration**: `children` is a new, empty mapping at ERC-7201 offset 4. Existing `PolicyRegistry` state at offsets 0–3 is unmodified by Cobalt activation.