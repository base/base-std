# Changelog

This document tracks behavioral changes to the Base precompile standard, organized by hardfork.
Each section is a complete summary of that hardfork's changes. For selector-level detail (exact
function selectors, event topics, error codes, and edge-case behavior), see the corresponding entry
in [`changelog/`](changelog/README.md).

## Denim

### Status

Denim has not activated yet. Operator allowance behavior remains unavailable until Denim selects B20 logic v3.

### Compatibility

Denim changes the behavior of existing `allowance`, `transferFrom`, and `transferFromWithMemo` selectors. It also moves the existing Asset `OPERATOR_ROLE()` getter onto the shared `IB20` surface, which makes that selector available on Stablecoin.

### Summary of changes

| Product | Feature | Change | Details |
| --- | --- | --- | --- |
| B20 (Asset and Stablecoin) | Issuer-approved operators | An account with `OPERATOR_ROLE` reads as having infinite allowance from every holder. Operator transfers do not consume stored allowances, but pause and transfer policies remain active. | [03_Denim_B20_operator_allowance](changelog/03_Denim_B20_operator_allowance.md) |

### Migration guidance

#### Issuers

Audit every existing `OPERATOR_ROLE` holder before Denim activates. Asset already uses this role for announcements and multiplier administration, so those accounts gain authority to move holder balances. Stablecoin issuers must also audit generic grants of the same role hash. Revoke any assignment that should not gain this authority.

#### Wallets and integrators

Treat `allowance(owner, spender) == type(uint256).max` as possible role-based authority. A holder cannot revoke that authority with `approve(spender, 0)`; only the role administrator can remove it. Continue to enforce transfer policy failures and paused-transfer failures for operator calls.

## Cobalt

### Status

Cobalt hasn't activated yet. Only the Beryl surface exists on-chain, so every selector, event, and
error introduced in this section is undialable until Cobalt activates.

### Compatibility

Cobalt is additive-only. It doesn't change or remove any Beryl selector, event topic, or error
selector. If a Cobalt symbol supersedes a Beryl one, the old symbol is deprecated, not deleted, and
you can still call it.

### Summary of changes

| Product | Feature | Change | Details |
| --- | --- | --- | --- |
| B20 Asset | Schedule Multiplier Updates ([ERC-8056](https://eips.ethereum.org/EIPS/eip-8056)) | The multiplier surface becomes ERC-8056 conformant (`uiMultiplier`, `toUIAmount`/`fromUIAmount`, `balanceOfUI`, `totalSupplyUI`) and gains a scheduled setter, `updateUIMultiplier`, for corporate actions. The existing instant setter, `updateMultiplier`, remains as an admin failsafe. | [02_Cobalt_B20Asset_multiplier](changelog/02_Cobalt_B20Asset_multiplier.md) |
| B20 (Asset and Stablecoin) | Seize surface, `burnBlocked` deprecation | Adds `seizeWithMemo`, an admin balance-reassignment operation gated by `SEIZE_ROLE`, a new `SEIZE` pause vector, and two new policy slots. `burnBlocked` is deprecated in its favor but still callable, unchanged. | [02_Cobalt_B20_seize](changelog/02_Cobalt_B20_seize.md) |
| PolicyRegistry | Composite policies (`UNION`/`INTERSECT`) | Adds policies that authorize by combining 2–4 existing simple policies under an OR (`UNION`) or AND (`INTERSECT`) gate. Create and update them with `createCompositePolicy` and `updateComposite`. | [02_Cobalt_PolicyRegistry_composite_policy](changelog/02_Cobalt_PolicyRegistry_composite_policy.md) |

### Migration guidance

#### B20 Asset: multiplier callers

Adopt the ERC-8056 names. Move routine multiplier changes from `updateMultiplier(uint256)` to the
scheduled `updateUIMultiplier(uint256,uint256)`.

#### B20 Asset and Stablecoin: `burnBlocked` callers

Replace administrative balance removal with `seizeWithMemo(from, treasury, amount, memo)`, then call
`burn(amount)` if you still need to destroy supply. Seize is opt-in per token: it has no effect
until the issuer sets `SEIZE_EXEMPT_POLICY`.

#### PolicyRegistry integrators

Use `createCompositePolicy` in place of OR/AND membership logic that you currently implement
off-chain or duplicate across multiple simple policies. This is optional: `createPolicy` and
`createPolicyWithAccounts` only gain one new revert path (rejecting a composite `policyType`,
previously unreachable), so no other integration change is required.
