# Composite Policies (UNION/INTERSECT)

- **Feature Name**: composite_policy
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Composite Policies (UNION/INTERSECT)

## Summary

This change introduces two new `PolicyRegistry` policy types: `UNION` (OR) and `INTERSECT` (AND). These composite policies authorize by combining 2 to 4 existing simple policies. The feature is intended for users of the policy registry who want to combine multiple policies without flattening them into a single large list. Composite policies reference only existing simple policies (`ALLOWLIST` or `BLOCKLIST`), never other composites or built-in sentinels (`ALWAYS_ALLOW` or `ALWAYS_BLOCK`). This constraint is enforced at write time. The feature ships at the **Cobalt** hardfork. Every mutating call (`createCompositePolicy`, `updateComposite`) is gated by `ActivationRegistry`, the same as every other mutating `PolicyRegistry` function. Read-only calls (`isAuthorized`, `compositePolicyChildIds`, `MIN_COMPOSITE_CHILD_POLICIES`, `MAX_COMPOSITE_CHILD_POLICIES`) are always callable regardless of activation status.

## Motivation

The policy registry currently supports simple boolean policies via `isAuthorized`, where each policy independently returns true or false. In practice, access control often requires combining multiple policies. For example, a system may need KYC plus ProUser, or ProUser OR LifetimeUser. The current architecture requires a user to listen to changes on a different allowlist and flatten it into one, which duplicates lists and requires infrastructure to keep them up to date. This change allows policy reuse by creating composite policies that reference other simple policies. A composite policy returns "is authorized" by combining the results of its child policies. This simplifies maintenance because updating one child policy updates every composite that references it.

## Background

### B20 Token

B20 is a token precompile that uses policies to restrict operations such as transfers, minting, and seizing. For each restricted operation, B20 stores a Policy Registry policy ID in a dedicated policy scope. When an operation is attempted, B20 passes the relevant policy ID and account address to the Policy Registry. If the account is not authorized, B20 rejects the operation.

### Policy Registry

The Policy Registry is a singleton precompile contract used by B20 tokens. It manages a list of policies. B20 tokens call `isAuthorized(policyId, account)` against a policy ID stored on the relevant policy scope. Currently, B20 tokens use the Policy Registry for `TRANSFER_FROM`, `TRANSFER_TO`, and `SEIZE_HOLDER`.

### Simple Policies

Simple policies are the non-composite policy types: `ALLOWLIST` and `BLOCKLIST`.

- `ALLOWLIST` has a list of addresses. It returns authorized `true` if the address is in the list, `false` otherwise.
- `BLOCKLIST` has a list of addresses. It returns authorized `false` if the address is in the list, `true` for all other addresses.

## Specs

### Interface Changes

The following interface delta is verified via `cast sig` or `cast keccak` against `src/interfaces/IPolicyRegistry.sol`:

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
| `createPolicy(address,uint8)` | `0xca5d55f6` | extended | Does not accept composite policy types; reverts with `IncompatiblePolicyType` (see below) |
| `createPolicyWithAccounts(address,uint8,address[])` | `0xa2d3044f` | extended | Same composite-policy-type rejection |

**Solidity interface additions:**

```solidity
// SPDX-License-Identifier: MIT
// File: src/interfaces/IPolicyRegistry.sol

interface IPolicyRegistry {
    // New enum values (UNION = 2, INTERSECT = 3)
    enum PolicyType {
        ALLOWLIST,
        BLOCKLIST,
        UNION,
        INTERSECT
    }

    // New errors
    error ChildPoliciesOutsideOfRange();
    error InvalidChildPolicy(uint64 childPolicyId);

    // New events
    event CompositePolicyUpdated(
        uint64 indexed policyId,
        address indexed updater,
        uint64[] childPolicyIds
    );

    // New functions
    function createCompositePolicy(
        address admin,
        PolicyType policyType,
        uint64[] calldata childPolicyIds
    ) external returns (uint64 policyId);

    function updateComposite(
        uint64 policyId,
        uint64[] calldata childPolicyIds
    ) external;

    function compositePolicyChildIds(uint64 policyId)
        external
        view
        returns (uint64[] memory);

    function MIN_COMPOSITE_CHILD_POLICIES() external pure returns (uint256);
    function MAX_COMPOSITE_CHILD_POLICIES() external pure returns (uint256);

    // Extended: now dispatches composites
    function isAuthorized(uint64 policyId, address account)
        external
        view
        returns (bool);

    // Extended: reject UNION/INTERSECT
    function createPolicy(address admin, PolicyType policyType)
        external
        returns (uint64 policyId);

    function createPolicyWithAccounts(
        address admin,
        PolicyType policyType,
        address[] calldata accounts
    ) external returns (uint64 policyId);
}
```

Two new values are introduced in the `PolicyType` enum:

- `UNION = 2` — authorized if *any* child policy authorizes the account (OR)
- `INTERSECT = 3` — authorized only if *every* child policy authorizes the account (AND)

#### `createCompositePolicy(admin, policyType, childPolicyIds)`

- `childPolicyIds` must be between 2 and 4 entries (`MIN_COMPOSITE_CHILD_POLICIES` / `MAX_COMPOSITE_CHILD_POLICIES`). The cap of 4 bounds worst-case `isAuthorized` gas and the authorization audit surface.
- Every child must be an *existing simple* policy (`ALLOWLIST` or `BLOCKLIST`) — never another composite, never a built-in sentinel (`ALWAYS_ALLOW` or `ALWAYS_BLOCK`).
- Canonical revert order:
  1. `ZeroAddress` (admin)
  2. `IncompatiblePolicyType` (policyType not UNION/INTERSECT)
  3. `ChildPoliciesOutsideOfRange` (count not in `[2,4]`)
  4. `PolicyNotFound` (a child doesn't exist, checked as one pass over the whole set)
  5. `InvalidChildPolicy` (a child is itself composite/sentinel, checked as a second pass)
- Emits, in order:
  1. `PolicyCreated(policyId, creator, policyType)`
  2. `PolicyAdminUpdated(policyId, address(0), admin)`
  3. `CompositePolicyUpdated(policyId, creator, childPolicyIds)`

#### `updateComposite(policyId, childPolicyIds)`

- Full replacement of the child set. There is no partial-update or clear-the-list operation.
- Same child-validity rules as `createCompositePolicy` (existing simple policies only, 2 to 4 of them).
- Canonical revert order:
  1. `PolicyNotFound` (composite itself doesn't exist)
  2. `IncompatiblePolicyType` (`policyId` is a simple policy)
  3. `Unauthorized` (caller isn't the current admin — fires before the count check)
  4. `ChildPoliciesOutsideOfRange`
  5. `PolicyNotFound` (a new child doesn't exist)
  6. `InvalidChildPolicy`
- Emits only `CompositePolicyUpdated(policyId, updater, childPolicyIds)`. No `PolicyAdminUpdated` is emitted because the admin does not change.

#### Existing functions with changed revert behavior for identical calldata

`createPolicy` and `createPolicyWithAccounts` (both already live on Beryl) are simple-policy constructors. They do not accept composite policy types and revert with `IncompatiblePolicyType`.

This is not merely a newly-reachable branch. The revert for the *same calldata* changes across the fork. Pre-Cobalt the `PolicyType` enum had only `BLOCKLIST` and `ALLOWLIST`, so calldata carrying type byte `2` or `3` failed ABI enum decode (Solidity reference: `Panic(0x21)`, enum-conversion out of range). Post-Cobalt byte `2` or `3` decodes cleanly as `UNION` or `INTERSECT`, then the explicit guard reverts `IncompatiblePolicyType`.

[TODO: verify against source] The exact pre-Cobalt revert of the *Rust precompile* for an out-of-range `PolicyType` byte is not asserted here. The Solidity mock does not model ABI enum decode. Confirm via `base-forge test` before publishing, or document only as Solidity-reference behaviour.

### Behavioural Changes

- A composite policy ID is passed to a B20 policy slot exactly like a simple policy ID. B20 needs **zero code changes**, since it stores policy slots as an opaque `uint64` and calls `isAuthorized` generically.
- `isAuthorized` on a composite is live and short-circuiting, not a snapshot:
  - It reads each child's *current* membership on every call. There is no snapshot from creation or the last `updateComposite`.
  - `UNION` short-circuits `true` on the first authorizing child.
  - `INTERSECT` short-circuits `false` on the first non-authorizing child.
  - Recursion never exceeds depth 1, because every child is validated to be a simple policy at write time. A composite's children can never themselves be composites.
- `isAuthorized` on a well-formed but **never-created** composite ID collapses to empty-child-set semantics:
  - `UNION` → `false` (deny-all)
  - `INTERSECT` → `true` (**allow-all** — an AND over zero children is vacuously true).
  This parallels the simple-policy empty-set rule (ALLOWLIST → `false`, BLOCKLIST → `true`). Consumers that store a composite ID (e.g., on a B20 policy slot) MUST validate `policyExists(policyId)` at write time. A typo'd INTERSECT ID would silently behave as `ALWAYS_ALLOW`.
- Gas: a composite reads more policy IDs than a simple policy (its child list, plus each evaluated child's membership), so `isAuthorized` on a composite costs more gas than on a simple policy.
- Child order affects gas, never the outcome:
  - `UNION` and `INTERSECT` are commutative, so reordering `childPolicyIds` never changes whether an account is authorized.
  - It only shifts where the short-circuit lands. Put the child most likely to short-circuit first (broadest ALLOWLIST for `UNION`, tightest BLOCKLIST for `INTERSECT`) to save gas.
- Duplicate child IDs are allowed. The registry neither sorts nor deduplicates the stored child list. Deduplicating would cost extra gas on every write for a set already capped at 4 entries, for little value. `UNION` and `INTERSECT` are idempotent under duplicates anyway.
- A composite can never shrink below 2 children via `updateComposite`. It enforces the same `[2,4]` range as creation, so there is no path to an empty or undersized composite.
- If a child policy's admin renounces, the parent composite keeps working. `renounceAdmin` only clears the child's admin and freezes its future membership changes. The child still exists and `isAuthorized` on it still resolves normally, so the composite keeps evaluating it exactly as before.
- State changes:
  - New state: `mapping(uint64 policyId => uint64[] childPolicyIds) children`, appended at **offset 4** within the `base.policy_registry` ERC-7201 namespace (not a literal EVM slot 4). It is appended so existing state at offsets 0–3 is unmodified and no storage migration is needed.
  - Reused state: one shared global counter (`nextCounter`) across simple and composite policies, starting at 2 (`0` and `1` are reserved for `ALWAYS_ALLOW` and `ALWAYS_BLOCK`). A composite policy ID encodes `PolicyType` in the top byte and the next available counter value in the low 56 bits. This uses the same encoding scheme as simple policies, not a separate counter.

### Examples

#### Before (simple policy)

- Assign one existing policy directly to a B20 policy scope:
  ```solidity
  b20.updatePolicy(TRANSFER_SENDER_POLICY, allowlistPolicyId)
  ```
- Only accounts in `allowlistPolicyId` can transfer.

#### After (composite policy)

- Assume existing simple policies: `employeesPolicyId` (ALLOWLIST), `approvedRegionPolicyId` (ALLOWLIST).
- Create a UNION composite:
  ```solidity
  policyRegistry.createCompositePolicy(admin, UNION, [employeesPolicyId, approvedRegionPolicyId])
  ```
- Emits: `PolicyCreated(policyId, admin, UNION)` + `PolicyAdminUpdated(policyId, 0, admin)` + `CompositePolicyUpdated(policyId, admin, [children])`.
- Assign to B20:
  ```solidity
  b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId)
  ```
- B20 has no composite-specific logic. It passes the policy ID to the registry as usual.

#### Updating a composite

- Call:
  ```solidity
  policyRegistry.updateComposite(compositePolicyId, [employeesPolicyId, trustedPartnersPolicyId])
  ```
- Emits: `CompositePolicyUpdated(policyId, admin, [newChildren])`.
- B20 continues using the same policy ID. No token-side update is required.
- Future authorization checks use the new child set immediately (live evaluation, no snapshot).

## Design Decisions & Alternatives Considered

### Decision: Two explicit policy types (`UNION`, `INTERSECT`) with a single `createCompositePolicy` function and full-replacement `updateComposite`

### Alternative 1: One generic COMPOSITE type

- Store a separate operator (AND, OR, NOT, XOR) in composite storage.
- Rejected because:
  - Requires storing both "composite" flag and the operator.
  - Adds storage reads or more complicated ID encoding.
  - Unnecessary complexity before there is a requirement for NOT, XOR, or nested expressions.
  - Generic boolean expressions create a larger gas and audit surface.

### Alternative 2: Token-level policy groups

- Keep Policy Registry unchanged; have each B20 token store multiple policy IDs and an operator.
- Rejected because:
  - Composite policies would not be reusable entities.
  - Requires changes across B20, token variants, factories, and token hot paths.
  - Does not support sharing one composite policy across multiple tokens.
  - Spreads complexity across more contracts.

### Alternative 3: Incremental child updates

- Provide `addCompositeOperand` and `removeCompositeOperand` functions.
- Rejected because:
  - Child list is capped at 4 entries.
  - Dynamic-array mutation requires swap/remove, length, and deduplication logic.
  - Full replacement is simpler and atomic.
  - Caller can resend the complete list at low cost.

### Alternative 4: Separate creator functions

- Use `createUnionPolicy` and `createIntersectPolicy`.
- Rejected because:
  - Doubles the creation API surface.
  - A single `createCompositePolicy` keeps policy creation consistent.
  - Future operators would require additional functions.

### Alternative 5: Nested composites (a composite referencing another composite)

- Allow composite children, to some bounded depth, instead of restricting children to simple `ALLOWLIST` and `BLOCKLIST` policies.
- Rejected because:
  - Restricting children to simple policies guarantees `isAuthorized` recursion terminates at depth 1. There is no cycle risk and no unbounded traversal.
  - Bounds worst-case gas and the audit surface of authorization evaluation.
  - No demonstrated need for nested expressions. A wrapper composite can be introduced later if one ever arises.

## Migration Steps

- **Backwards-compatible**: Existing simple policies (ALLOWLIST and BLOCKLIST) continue to work unchanged. No action is required if you do not need composite behavior.

- **For users currently flattening multiple lists into one policy**:
  1. Identify the simple policies you want to combine.
  2. Call `policyRegistry.createCompositePolicy(admin, UNION or INTERSECT, [childPolicyIds])`.
  3. Update the B20 token's policy scope to point to the new composite policy ID:
     ```solidity
     b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId)
     ```
     No B20 contract change is required. B20 treats the composite ID as an opaque `uint64` exactly like a simple policy ID.
  4. Remove the old flattened policy if no longer needed.

- **No breaking changes**: All existing selectors, events, and errors remain dialable at Cobalt.

- **No storage migration**: `children` is a new, empty mapping at ERC-7201 offset 4. Existing `PolicyRegistry` state at offsets 0–3 is unmodified by Cobalt activation.