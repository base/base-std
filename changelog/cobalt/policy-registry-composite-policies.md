# PolicyRegistry — composite policies (UNION / INTERSECT)

> **Audience:** teams integrated against `PolicyRegistry` on **Beryl** (live today) — creating and
> administering simple `ALLOWLIST`/`BLOCKLIST` policies, and referencing policy IDs on B20 policy
> slots. This note covers **only** the composite (`UNION`/`INTERSECT`) policy support landing at the
> **Cobalt** hardfork.

## Summary

At Cobalt, `PolicyRegistry` gains **composite policies**: a policy that authorizes by combining 2–4
existing *simple* policies under a `UNION` (OR) or `INTERSECT` (AND) gate, created with the new
`createCompositePolicy` and mutated in full with the new `updateComposite`. **Nothing you call today
breaks.** Every Beryl selector, event topic, and error keeps its exact 4-byte selector / topic0 and
stays dialable at Cobalt. The only change to existing behavior: `createPolicy` and
`createPolicyWithAccounts` gain one new — previously unreachable — revert path, rejecting a
composite `policyType` with the already-existing `IncompatiblePolicyType` error. **Cobalt is not
live yet**; until it activates, only the Beryl (simple-policy) surface exists on-chain, and every
composite selector below is undialable.

## Mapping table

Selectors and topic0s below are computed directly from `src/interfaces/IPolicyRegistry.sol` with
`cast sig` / `cast sig-event`; all Beryl symbols keep their selector at Cobalt.

### `PolicyType` enum

| Beryl | Cobalt addition | Why |
| --- | --- | --- |
| `BLOCKLIST = 0`, `ALLOWLIST = 1` | `UNION = 2`, `INTERSECT = 3` | Append-only — existing values and the packed-ID top-byte encoding are unchanged. |

### Functions

| Beryl symbol (selector) | Cobalt (selector) | Status | Why |
| --- | --- | --- | --- |
| `createPolicy(address,uint8)` `0xca5d55f6` | unchanged | present on Beryl already, new revert path | Now also reverts `IncompatiblePolicyType` when `policyType` is `UNION`/`INTERSECT`, checked after `ZeroAddress`. |
| `createPolicyWithAccounts(address,uint8,address[])` `0xa2d3044f` | unchanged | present on Beryl already, new revert path | Same composite-type rejection, checked after `ZeroAddress` and before `BatchSizeTooLarge`. |
| — | `createCompositePolicy(address,uint8,uint64[])` `0x6fdd1491` | new | Creates a `UNION`/`INTERSECT` policy from 2–4 existing simple policy IDs. |
| — | `updateComposite(uint64,uint64[])` `0xbfe142c0` | new | Replaces a composite's child-policy set in full — no partial-update or clear-the-list path. |
| — | `compositePolicyChildIds(uint64)` `0x7c40df74` | new | Read-only child-set getter. Always callable (not gated). |
| — | `MIN_COMPOSITE_CHILD_POLICIES()` `0xb3ae29f7` | new | Constant `2`. Always callable. |
| — | `MAX_COMPOSITE_CHILD_POLICIES()` `0x54309870` | new | Constant `4`. Always callable. |

`isAuthorized(uint64,address)` `0x55a1179e`, `policyExists(uint64)` `0x330f5637`,
`policyAdmin(uint64)` `0x09dd0a47`, `pendingPolicyAdmin(uint64)` `0x017548b7`,
`updateAllowlist(uint64,bool,address[])` `0x3388fb5b`, `updateBlocklist(uint64,bool,address[])`
`0x5c4e51b8`, `stageUpdateAdmin(uint64,address)` `0x1d7ae695`, `finalizeUpdateAdmin(uint64)`
`0x33031a9c`, and `renounceAdmin(uint64)` `0xefdb7fa3` are carried over unchanged.

### Events

| Beryl event (topic0) | Cobalt (topic0) | Status | Why |
| --- | --- | --- | --- |
| `PolicyCreated(uint64,address,uint8)` `0x718d…2ec27` | unchanged | carried over | Also emitted for composite creation, with `policyType` `UNION`/`INTERSECT`. |
| — | `CompositePolicyUpdated(uint64,address,uint64[])` `0x4ff6adaab31b0df87aa7b8b7320c52b8b3b5eede3bf28a6baaaa8b8b7e1d6363` | new | Emitted on composite creation **and** every `updateComposite`; carries the complete post-update child set. |

`PolicyAdminStaged`, `PolicyAdminUpdated`, `AllowlistUpdated`, and `BlocklistUpdated` are carried
over unchanged and are not emitted for composites (composites have no membership set of their own).

### Errors

| Beryl error (selector) | Cobalt (selector) | Status | Why |
| --- | --- | --- | --- |
| `IncompatiblePolicyType()` `0xf1011ef5` | unchanged | present on Beryl already, new call sites | Now also thrown by `createPolicy`/`createPolicyWithAccounts` (composite `policyType` passed to a simple constructor), `createCompositePolicy` (`policyType` isn't `UNION`/`INTERSECT`), and `updateComposite` (target isn't a composite). |
| `PolicyNotFound()` `0x720caa4f` | unchanged | present on Beryl already, new call sites | Now also thrown for the composite target itself in `updateComposite`, and for any nonexistent child in `createCompositePolicy`/`updateComposite`. |
| — | `ChildPoliciesOutsideOfRange()` `0x697ec868` | new | Child count outside `[MIN_COMPOSITE_CHILD_POLICIES, MAX_COMPOSITE_CHILD_POLICIES]` (`[2, 4]`). |
| — | `InvalidChildPolicy(uint64)` `0x46508ef6` | new | A child is itself a composite, or a built-in sentinel (`ALWAYS_ALLOW`/`ALWAYS_BLOCK`). |

## New at Cobalt (adopt these)

### `createCompositePolicy(admin, policyType, childPolicyIds)`

Creates a `UNION`/`INTERSECT` policy over 2–4 existing simple policy IDs. Canonical revert
precedence — each check fires before the next, in this order:

1. `ZeroAddress` — `admin == address(0)`.
2. `IncompatiblePolicyType` — `policyType` is not `UNION`/`INTERSECT`.
3. `ChildPoliciesOutsideOfRange` — `childPolicyIds.length` outside `[2, 4]`.
4. `PolicyNotFound` — any child does not exist (checked as one pass over the whole set, before the
   next check).
5. `InvalidChildPolicy` — any child is a composite or a built-in sentinel (second pass).

On success, emits `PolicyCreated(policyId, creator, policyType)`,
`PolicyAdminUpdated(policyId, 0, admin)`, then `CompositePolicyUpdated(policyId, creator, childPolicyIds)`.

### `updateComposite(policyId, childPolicyIds)`

Replaces a composite's child-policy set **in full** — a child omitted from the new set no longer
governs the composite; there is no partial-update or clear-the-list path. Canonical order:

1. `PolicyNotFound` — `policyId` does not exist.
2. `IncompatiblePolicyType` — `policyId` is a simple policy, not a composite.
3. `Unauthorized` — caller is not the current admin. A renounced composite (admin `address(0)`) can
   never be updated.
4. `ChildPoliciesOutsideOfRange` — new count outside `[2, 4]`.
5. `PolicyNotFound` — any new child does not exist.
6. `InvalidChildPolicy` — any new child is a composite or a built-in sentinel.

Emits `CompositePolicyUpdated(policyId, updater, childPolicyIds)`.

### Live, depth-1 evaluation

`isAuthorized` on a composite re-reads each child's **current** membership on every call — never a
snapshot taken at creation or last update. `UNION` returns `true` on the first authorizing child
(short-circuits); `INTERSECT` returns `false` on the first non-authorizing child. Recursion never
exceeds depth 1: every child is validated to be a simple (`ALLOWLIST`/`BLOCKLIST`) policy at write
time, so a composite's children can never themselves be composites.

## Guarantees / edge cases

**Q: Can a composite's child be another composite (nested composites)?**
No. `createCompositePolicy` and `updateComposite` revert `InvalidChildPolicy(childPolicyId)` for any
child whose type is `UNION`/`INTERSECT`. Nesting is impossible by construction.

**Q: Can a built-in sentinel (`ALWAYS_ALLOW`/`ALWAYS_BLOCK`) be a composite child?**
No — same `InvalidChildPolicy` revert. To mix always-allow/always-block behavior into a composite
gate, use a real `ALLOWLIST`/`BLOCKLIST` policy that reproduces the desired effect instead.

**Q: Can I pass the same child ID twice, or shrink a composite below 2 children?**
Duplicates are permitted — the registry neither sorts nor de-duplicates the stored child list (extra
evaluation cost only; `UNION`/`INTERSECT` are idempotent under duplicates). Shrinking below 2 is not
possible: every `updateComposite` call re-enforces the same `[2, 4]` range as creation, so there is
no path to an empty or under-sized composite.

**Q: If a child policy's admin renounces, does the parent composite break?**
No. `renounceAdmin` on the child only clears its admin and freezes its *future* membership changes —
the child still exists and `isAuthorized` on it still resolves normally, so the composite keeps
evaluating it exactly as before.

**Q: Is composite mutation gated separately from simple-policy mutation?**
No. `createCompositePolicy` and `updateComposite` are gated by the same `ActivationRegistry` flag
that gates `createPolicy`, `updateAllowlist`, etc. — there is no composite-specific activation flag.
`compositePolicyChildIds`, `MIN_COMPOSITE_CHILD_POLICIES`, `MAX_COMPOSITE_CHILD_POLICIES`, and
`isAuthorized` on a composite ID are all always callable, whether or not the feature is active.

**Q: Can a B20 token's policy slot (e.g. `TRANSFER_SENDER_POLICY`, `SEIZE_HOLDER_POLICY`) reference a
composite ID?**
Yes. B20 stores every policy slot as an opaque `uint64 policyId` and calls `isAuthorized` — a
composite ID works exactly like a simple one, and no B20-side change was needed. As with any policy
ID, validate `policyExists(policyId)` before writing it to a slot.
