# ADR Template (Point Form)

- **Feature Name**: composite_policy
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Composite Policies (UNION/INTERSECT)

---

## Summary

- Introduce two new `PolicyRegistry` policy types, `UNION` (OR) and `INTERSECT` (AND) — collectively
  "composite policies" — that authorize by combining 2 to 4 existing simple policies
- For users utilizing the policy registry who may want to combine many policies together, without
  flattening into one big list
- Composite policies are built up of only existing simple policies (`ALLOWLIST`/`BLOCKLIST`) — never
  another composite, and never a built-in sentinel (`ALWAYS_ALLOW`/`ALWAYS_BLOCK`)
- Ships at the **Cobalt** hardfork. Every mutating call (`createCompositePolicy`, `updateComposite`)
  is gated by `ActivationRegistry`, same as every other mutating `PolicyRegistry` function — not
  automatically enabled. Read-only calls (`isAuthorized`, `compositePolicyChildIds`,
  `MIN_COMPOSITE_CHILD_POLICIES`, `MAX_COMPOSITE_CHILD_POLICIES`) are always callable regardless of
  activation

---

## Motivation

> State the problem this change solves, why the current state is insufficient, and brief context
> on prerequisites if needed (full detail lives in Background).
- The policy registry currently supports simple boolean policies via `isAuthorized`, where each
  policy independently returns true or false
- In practice, access control often requires combining multiple policies (e.g., KYC + ProUser, or
  ProUser OR LifetimeUser)
- The current architecture requires a user to listen to changes on a different allowlist and
  flatten into one, duplicating lists and requiring infra to keep them up to date
- We want to allow for policy reuse by creating composite policies which can reference other simple
  policies
    - should return "is authorized" by combining the results of other policies
    - simplifies maintenance — updating one child policy updates every composite that references it

---

## Background

> Link to or summarize concepts the reader needs before understanding the Specs: prior art,
> relevant EIPs/ERCs, existing patterns, and any domain-specific terms used in this document.
- B20 Token
    - B20 is a token precompile that uses policies to restrict operations such as
    transfers, minting, and seizing.
    - For each restricted operation, B20 stores a Policy Registry policy ID in a
    dedicated policy scope.
    - When an operation is attempted, B20 passes the relevant policy ID and account
    address to the Policy Registry. If the account is not authorized, B20
    rejects the operation.

- Policy Registry:
    - Is a singleton precompile contract used by B20 tokens.
    - It manages a list of policies; B20 tokens call `isAuthorized(policyId, account)` against a
      policy ID stored on the relevant policy scope
    - Currently used by B20 tokens for `TRANSFER_FROM`, `TRANSFER_TO`, `SEIZE_HOLDER`
- Simple policies:
    - These are the non-composite policy types: `ALLOWLIST` / `BLOCKLIST`
        - `ALLOWLIST` has a list of addresses; returns authorized `true` if the address is in the
          list, `false` otherwise
        - `BLOCKLIST` has a list of addresses; returns authorized `false` if the address is in the
          list, `true` for all other addresses

---

## Specs

> Implementation details live here. Add more headings as needed (e.g., Storage Layout Changes,
> Deprecated Assets, Access Control, etc.).


### Interface Changes

> New functions, events, errors (include signatures). Renamed or deprecated symbols (old → new).
> Selector / topic0 values (verified via `cast sig` or `cast keccak`).

- Introduce 2 new values in the `PolicyType` enum
    - `UNION = 2` — authorized if *any* child policy authorizes the account (OR)
    - `INTERSECT = 3` — authorized only if *every* child policy authorizes the account (AND)
- New function `createCompositePolicy(admin, policyType, childPolicyIds)`
    - `childPolicyIds` must be between 2 and 4 entries (`MIN_COMPOSITE_CHILD_POLICIES` /
      `MAX_COMPOSITE_CHILD_POLICIES`)
    - Every child must be an *existing simple* policy (`ALLOWLIST`/`BLOCKLIST`) — never another
      composite, never a built-in sentinel (`ALWAYS_ALLOW`/`ALWAYS_BLOCK`)
    - Canonical revert order: `ZeroAddress` (admin) → `IncompatiblePolicyType` (policyType not
      UNION/INTERSECT) → `ChildPoliciesOutsideOfRange` (count not in `[2,4]`) → `PolicyNotFound`
      (a child doesn't exist, checked as one pass over the whole set) → `InvalidChildPolicy` (a
      child is itself composite/sentinel, checked as a second pass)
    - Emits, in order: `PolicyCreated(policyId, creator, policyType)`,
      `PolicyAdminUpdated(policyId, address(0), admin)`, `CompositePolicyUpdated(policyId, creator,
      childPolicyIds)`
- New function `updateComposite(policyId, childPolicyIds)`
    - Full replacement of the child set — there's no partial-update or clear-the-list operation
    - Same child-validity rules as `createCompositePolicy` (existing simple policies only, 2-4 of
      them)
    - Canonical revert order: `PolicyNotFound` (composite itself doesn't exist) →
      `IncompatiblePolicyType` (`policyId` is a simple policy) → `Unauthorized` (caller isn't the
      current admin — fires before the count check) → `ChildPoliciesOutsideOfRange` →
      `PolicyNotFound` (a new child doesn't exist) → `InvalidChildPolicy`
    - Emits only `CompositePolicyUpdated(policyId, updater, childPolicyIds)` — no
      `PolicyAdminUpdated`, since admin doesn't change
- Existing function, new revert path: `createPolicy` and `createPolicyWithAccounts` (both already
  live on Beryl) now also revert `IncompatiblePolicyType` when `policyType` is `UNION`/`INTERSECT` —
  a previously-unreachable path, since those enum values didn't exist before Cobalt


### Behavioural Changes

> How execution flow differs from the previous version. Storage layout changes (new slots, moved
> fields, packing changes). Gas cost implications if meaningful.
- A composite policy ID is passed to a B20 policy slot exactly like a simple policy ID — B20 needs
  **zero code changes**, since it stores policy slots as an opaque `uint64` and calls
  `isAuthorized` generically
- `isAuthorized` on a composite is live and short-circuiting, not a snapshot:
    - Reads each child's *current* membership on every call — no snapshot from creation or the
      last `updateComposite`
    - `UNION` short-circuits `true` on the first authorizing child
    - `INTERSECT` short-circuits `false` on the first non-authorizing child
    - Recursion never exceeds depth 1, because every child is validated to be a simple policy at
      write time — a composite's children can never themselves be composites
- Child order affects gas, never the outcome:
    - `UNION`/`INTERSECT` are commutative, so reordering `childPolicyIds` never changes whether an
      account is authorized
    - It only shifts where the short-circuit lands — put the child most likely to short-circuit
      first (broadest ALLOWLIST for `UNION`, tightest BLOCKLIST for `INTERSECT`) to save gas
- Duplicate child IDs are allowed. The registry neither sorts nor deduplicates the stored child
  list — deduplicating would cost extra gas on every write for a set already capped at 4 entries,
  for little value; `UNION`/`INTERSECT` are idempotent under duplicates anyway
- A composite can never shrink below 2 children via `updateComposite` — it enforces the same
  `[2,4]` range as creation, so there's no path to an empty or undersized composite
- If a child policy's admin renounces, the parent composite keeps working: `renounceAdmin` only
  clears the child's admin and freezes its future membership changes. The child still exists and
  `isAuthorized` on it still resolves normally, so the composite keeps evaluating it exactly as
  before
- State changes
    - New state: `mapping(uint64 policyId => uint64[] childPolicyIds) children`, at **offset 4**
      within the `base.policy_registry` ERC-7201 namespace (not a literal EVM slot 4)
    - Reused state: one shared global counter (`nextCounter`) across simple and composite
      policies, starting at 2 (`0` and `1` are reserved for `ALWAYS_ALLOW`/`ALWAYS_BLOCK`). A
      composite policy ID encodes `PolicyType` in the top byte and the next available counter
      value in the low 56 bits — the same encoding scheme as simple policies, not a separate
      counter


### Examples

- **Before (simple policy)**:
    - Assign one existing policy directly to a B20 policy scope
    - `b20.updatePolicy(TRANSFER_SENDER_POLICY, allowlistPolicyId)`
    - Only accounts in `allowlistPolicyId` can transfer

- **After (composite policy)**:
    - Assume existing simple policies: `employeesPolicyId` (ALLOWLIST), `approvedRegionPolicyId` (ALLOWLIST)
    - Create a UNION composite:
        - `policyRegistry.createCompositePolicy(admin, UNION, [employeesPolicyId, approvedRegionPolicyId])`
    - Emits: `PolicyCreated(policyId, admin, UNION)` + `PolicyAdminUpdated(policyId, 0, admin)` +
      `CompositePolicyUpdated(policyId, admin, [children])`
    - Assign to B20: `b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId)`
    - B20 has no composite-specific logic — it passes the policy ID to the registry as usual

- **Updating a composite**:
    - `policyRegistry.updateComposite(compositePolicyId, [employeesPolicyId, trustedPartnersPolicyId])`
    - Emits: `CompositePolicyUpdated(policyId, admin, [newChildren])`
    - B20 continues using the same policy ID — no token-side update required
    - Future authorization checks use the new child set immediately (live evaluation, no snapshot)

---

## Design Decisions & Alternatives Considered

- **Decision**: Two explicit policy types (`UNION`, `INTERSECT`) with a single `createCompositePolicy` function and full-replacement `updateComposite`

- **Alternative 1: One generic COMPOSITE type**
    - Store a separate operator (AND, OR, NOT, XOR) in composite storage
    - Rejected:
        - Requires storing both "composite" flag and the operator
        - Adds storage reads or more complicated ID encoding
        - Unnecessary complexity before there's a requirement for NOT, XOR, or nested expressions
        - Generic boolean expressions create a larger gas and audit surface

- **Alternative 2: Token-level policy groups**
    - Keep Policy Registry unchanged; have each B20 token store multiple policy IDs + an operator
    - Rejected:
        - Composite policies would not be reusable entities
        - Requires changes across B20, token variants, factories, and token hot paths
        - Does not support sharing one composite policy across multiple tokens
        - Spreads complexity across more contracts

- **Alternative 3: Incremental child updates**
    - Provide `addCompositeOperand` / `removeCompositeOperand` functions
    - Rejected:
        - Child list is capped at 4 entries
        - Dynamic-array mutation requires swap/remove, length, and deduplication logic
        - Full replacement is simpler and atomic
        - Caller can resend the complete list at low cost

- **Alternative 4: Separate creator functions**
    - Use `createUnionPolicy` and `createIntersectPolicy`
    - Rejected:
        - Doubles the creation API surface
        - A single `createCompositePolicy` keeps policy creation consistent
        - Future operators would require additional functions

---

## Migration Steps

- **Backwards-compatible**: Existing simple policies (ALLOWLIST/BLOCKLIST) continue to work unchanged. No action required if you don't need composite behavior.

- **For users currently flattening multiple lists into one policy**:
    1. Identify the simple policies you want to combine
    2. Call `policyRegistry.createCompositePolicy(admin, UNION or INTERSECT, [childPolicyIds])`
    3. Update the B20 token's policy scope to point to the new composite policy ID:
        - `b20.updatePolicy(TRANSFER_SENDER_POLICY, compositePolicyId)`
        - No B20 contract change is required — B20 treats the composite ID as an opaque `uint64`
          exactly like a simple policy ID
    4. Remove the old flattened policy if no longer needed

- **No breaking changes**: All existing selectors, events, and errors remain dialable at Cobalt

- **No storage migration**: `children` is a new, empty mapping at ERC-7201 offset 4. Existing
  `PolicyRegistry` state at offsets 0–3 is unmodified by Cobalt activation
