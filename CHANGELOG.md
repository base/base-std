# Changelog

This document tracks behavioral changes to the Base precompile standard, organized by hardfork.
Each section below is a complete summary of one hardfork's changes. For selector-level detail —
exact function selectors, event topics, error codes, and edge-case behavior — see the corresponding
entry under [`changelog/`](changelog/README.md).

## Cobalt

### Status

Not activated. Only the Beryl surface exists on-chain. Every selector, event, and error introduced
in this section is undialable until Cobalt activates.

### Compatibility

Cobalt is additive-only. No Beryl selector, event topic, or error selector is changed or removed.
Symbols superseded by a Cobalt equivalent are deprecated, not deleted, and remain callable.

### Summary of changes

| Product | Feature | Change | Details |
| --- | --- | --- | --- |
| B20 Asset | Schedule Multiplier Updates ([ERC-8056](https://eips.ethereum.org/EIPS/eip-8056)) | The multiplier surface becomes ERC-8056 conformant (`uiMultiplier`, `toUIAmount`/`fromUIAmount`, `balanceOfUI`, `totalSupplyUI`) and gains a scheduled setter, `updateUIMultiplier`, for corporate actions. The existing instant setter, `updateMultiplier`, is retained as an admin failsafe. | [02_Cobalt_B20Asset_multiplier](changelog/02_Cobalt_B20Asset_multiplier.md) |
| B20 (Asset and Stablecoin) | Seize surface, `burnBlocked` deprecation | Adds `seizeWithMemo`, an admin balance-reassignment operation gated by `SEIZE_ROLE`, a new `SEIZE` pause vector, and two new policy slots. `burnBlocked` is deprecated in its favor but remains callable, unchanged. | [02_Cobalt_B20_seize](changelog/02_Cobalt_B20_seize.md) |
| PolicyRegistry | Composite policies (`UNION`/`INTERSECT`) | Adds policies that authorize by combining 2–4 existing simple policies under an OR (`UNION`) or AND (`INTERSECT`) gate, created and mutated via `createCompositePolicy` and `updateComposite`. | [02_Cobalt_PolicyRegistry_composite_policy](changelog/02_Cobalt_PolicyRegistry_composite_policy.md) |

### Migration guidance

#### B20 Asset: multiplier callers

Adopt the ERC-8056 names. Move routine multiplier changes from `updateMultiplier(uint256)` to the
scheduled `updateUIMultiplier(uint256,uint256)`.

#### B20 Asset and Stablecoin: `burnBlocked` callers

Replace administrative balance removal with `seizeWithMemo(from, treasury, amount, memo)`, followed
by `burn(amount)` if supply destruction is still required. Seize is opt-in per token: it has no
effect until the issuer sets `SEIZE_HOLDER_POLICY`.

#### PolicyRegistry integrators

Use `createCompositePolicy` in place of OR/AND membership logic implemented off-chain or duplicated
across multiple simple policies. This is optional — `createPolicy` and `createPolicyWithAccounts`
gain exactly one new revert path (rejecting a composite `policyType`, previously unreachable), and no
other integration is required to change.
