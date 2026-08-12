# Changelog

High-level, per-hardfork summary of behavioral changes to the Base precompile standard. Each
section below is a one-page overview of everything shipping at that hardfork. For the complete
migration notes on a given feature — exact selectors, topic0s, error codes, and edge-case Q&A — see
the linked entry under [`changelog/<hardfork>/`](changelog/README.md).

## Cobalt (upcoming)

**Status:** not live. Until Cobalt activates, only the Beryl surface exists on-chain, and every
selector, event, and error introduced below is undialable.

**Compatibility:** additive-only across all three features. No Beryl selector, event topic, or
error selector changes or is removed. Where a Beryl symbol is superseded, it is retained as
deprecated-but-dialable, never deleted.

| Product | Feature | What changes | Details |
| --- | --- | --- | --- |
| B20 Asset | Schedule Multiplier Updates ([ERC-8056](https://eips.ethereum.org/EIPS/eip-8056)) | Multiplier surface becomes ERC-8056 conformant (`uiMultiplier`, `toUIAmount`/`fromUIAmount`, `balanceOfUI`, `totalSupplyUI`) and gains a scheduled setter, `updateUIMultiplier`, for corporate actions. The instant `updateMultiplier` is kept as an admin failsafe. | [b20-asset-scheduled-multiplier-updates](changelog/cobalt/b20-asset-scheduled-multiplier-updates.md) |
| B20 (Asset + Stablecoin) | Seize + `burnBlocked` deprecation | Adds `seizeWithMemo`, an admin balance-reassignment op gated by `SEIZE_ROLE`, a new `SEIZE` pause vector, and two new policy slots. `burnBlocked` is deprecated in favor of it but stays callable unchanged. | [b20-seize-surface](changelog/cobalt/b20-seize-surface.md) |
| PolicyRegistry | Composite Policies (`UNION`/`INTERSECT`) | Adds policies that authorize by combining 2–4 existing simple policies under an OR (`UNION`) or AND (`INTERSECT`) gate, via `createCompositePolicy` / `updateComposite`. | [policy-registry-composite-policies](changelog/cobalt/policy-registry-composite-policies.md) |

### Migration checklist

- **B20 Asset multiplier callers:** adopt the ERC-8056 names, and move routine multiplier changes
  from `updateMultiplier(uint256)` to `updateUIMultiplier(uint256,uint256)`.
- **`burnBlocked` callers (Asset or Stablecoin):** replace administrative balance removal with
  `seizeWithMemo(from, treasury, amount, memo)`, followed by `burn(amount)` if supply destruction is
  still required. Seize is opt-in per token — it does nothing until the issuer sets
  `SEIZE_HOLDER_POLICY`.
- **PolicyRegistry integrators:** where OR/AND membership logic is currently reimplemented off-chain
  or duplicated across multiple simple policies, consider `createCompositePolicy` instead. No action
  is required otherwise — `createPolicy` and `createPolicyWithAccounts` only gain a new revert path
  for composite `policyType` values, which was previously unreachable.
