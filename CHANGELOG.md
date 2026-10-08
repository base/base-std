# Changelog

This document tracks behavioral changes to the Base precompile standard, organized by hardfork.
Each section is a complete summary of that hardfork's changes. For selector-level detail (exact
function selectors, event topics, error codes, and edge-case behavior), see the corresponding entry
in [`changelog/`](changelog/README.md).

## Denim

### Status

Denim hasn't activated yet. The Beryl and Cobalt surfaces are live on-chain. Every behavior change
and selector introduced in this section takes effect only once Denim activates.

### Compatibility

Denim doesn't remove or rename any selector, event topic, or error selector. It adds one
PolicyRegistry view function and the read-only `IBaseTime` interface for the new BaseTime predeploy,
neither of which changes an existing selector. It is **not** additive-only: two B20 changes alter
the outcome of existing calls.

- A transfer, mint, or seize whose recipient is the token's own address now reverts
  `InvalidReceiver(to)` where it previously succeeded.
- A token with a restrictive `TRANSFER_EXECUTOR_POLICY` now applies that policy to `transfer`,
  `transferWithMemo`, and self-`transferFrom`, so holders outside the policy can no longer move
  their own tokens. Tokens that never set the policy are unaffected.

### Summary of changes

| Product | Feature | Change | Details |
| --- | --- | --- | --- |
| B20 (Asset and Stablecoin) | Reject the token itself as a credit recipient (**breaking**) | `transfer`, `transferFrom`, their memo variants, `mint`, `mintWithMemo`, `batchMint`, and `seizeWithMemo` revert `InvalidReceiver(to)` when `to` is the token's own address. Self-transfers (`from == to`) still succeed, and `seizeWithMemo` from the token address still recovers balances already stuck there. | [03_Denim_B20_token_receiver](changelog/03_Denim_B20_token_receiver.md) |
| B20 (Asset and Stablecoin) | Transfer executor policy on every transfer path (**breaking**) | `TRANSFER_EXECUTOR_POLICY` checks `msg.sender` on `transfer`, `transferFrom`, and their memo variants, including when `msg.sender == from`. Previously it ran only on delegated `transferFrom`. No new selectors, events, errors, or storage. | [03_Denim_B20_transfer_executor_enforcement](changelog/03_Denim_B20_transfer_executor_enforcement.md) |
| BaseTime | Millisecond block timestamp | New predeploy at `0x4200000000000000000000000000000000000030`, exposed as `StdPredeploys.BASE_TIME`. `IBaseTime` provides `timestampMs()` (`block.timestamp * 1000 + timestampMillisPart()`), `timestampMillisPart()`, and `version()`. Read-only; the protocol writes the value each block. | [03_Denim_BaseTime_millisecond_timestamp](changelog/03_Denim_BaseTime_millisecond_timestamp.md) |
| PolicyRegistry | NOT / invert policies | Bit 63 of a policy ID becomes the invert bit: `isAuthorized` resolves the base policy and returns the opposite result, failing closed on an unknown base. Works for simple and composite policies and as a composite child. Adds the `invertedPolicyId(uint64)` view helper. | [03_Denim_PolicyRegistry_not_policy](changelog/03_Denim_PolicyRegistry_not_policy.md) |

### Migration guidance

#### B20: wallets, custodians, and indexers

Treat a token's own address as an invalid recipient, the same way you already treat `address(0)`,
and expect `InvalidReceiver` from sends to it. To recover a balance credited to the token address
before activation, call `seizeWithMemo(address(token), treasury, amount, memo)`; the token must be
seizable under `SEIZE_EXEMPT_POLICY` and the caller must hold `SEIZE_ROLE`.

#### B20: issuers with a `TRANSFER_EXECUTOR_POLICY`

If holders should keep initiating their own transfers, add them, or a policy covering them, to the
executor policy before Denim activates. Otherwise only accounts the policy authorizes, such as a
transfer agent calling `transferFrom`, can move tokens.

#### BaseTime readers

Read `StdPredeploys.BASE_TIME.timestampMs()` for the block timestamp in milliseconds. Until the
block's `tx[1]` deposit executes (for example, during the `tx[0]` L1-info deposit), it combines the
current block's seconds with the previous block's millisecond component.

#### PolicyRegistry integrators

Use `invertedPolicyId(policyId)` (or set bit 63) instead of maintaining a mirrored allowlist and
blocklist. This is optional: existing IDs have bit 63 unset and behave identically. Read views
(`policyExists`, `policyAdmin`, `pendingPolicyAdmin`, `compositePolicyChildIds`) resolve an
inverted ID to its base, so keep validating `policyExists(policyId)` at write time.

## Cobalt

### Status

Cobalt is live on-chain. Every selector, event, and error introduced in this section is callable.

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
