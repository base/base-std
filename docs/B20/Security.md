# B20 Security

The Security variant of B20 — designed for tokenized securities. Everything in [B20/README.md](README.md) applies; this page covers the deltas only. See [`IB20Security`](../../src/interfaces/IB20Security.sol) for the full Solidity interface.

## Share Ratio

Shares are a virtualized representation of an asset amount, computed by applying a uniform ratio on top of the underlying token balance stored on every account. The ratio applies to all accounts equally, which lets issuers model corporate actions like splits or reverse-splits without rewriting individual balances.

Read the current ratio with `sharesToTokensRatio()`; the value is in WAD precision (`1e18`, exposed as `WAD_PRECISION()`). `toShares(tokenAmount)` converts a token amount to shares at the current ratio, and `sharesOf(account)` is a convenience over ERC-20's `balanceOf` that returns the same account's balance expressed in shares.

`updateShareRatio(newRatio)` updates the ratio and should be wrapped in an announcement (see [Announcements](#announcements)).

## Announcements

Announcements are publicly viewable notifications posted by a token operator. They can represent anything the operator wants to create a record of and can be coupled with actual state changes on the token (updating share ratio, batched mints/burns, updating identifiers, and so on).

### Event Topology

An announcement is delimited by a paired `Announcement(msg.sender, id, description, uri)` event (opens the bracket) and `EndAnnouncement(id)` event (closes it). Every state-changing call dispatched inside the bracket belongs to that announcement. A recursion guard prevents nesting, and each `id` is enforced unique forever (`AnnouncementIdAlreadyUsed`) so indexers can correlate brackets across transactions.

Indexers should treat every `Announcement` log as the start of exactly one bracket; effects between `Announcement` and `EndAnnouncement` belong to the announced action; effects emitted *without* a surrounding bracket are direct invocations and should be flagged as emergency overrides.

### Wrapping calls in announcements

Wrap a set of operations in a single announcement by calling `announce(internalCalls, id, description, uri)`. The function (gated by `SECURITY_OPERATOR_ROLE`) emits `Announcement`, dispatches each internal call via self-`delegatecall` (which preserves `msg.sender` so the inner role checks see the operator), then emits `EndAnnouncement`. Inner reverts are wrapped in `InternalCallFailed` rather than bubbled — replay the call directly to debug. Nested calls to `announce` revert with `AnnouncementInProgress`; calls shorter than 4 bytes revert with `InternalCallMalformed`.

```solidity
// Disclose and execute a 2-for-1 forward split atomically.
bytes[] memory internalCalls = new bytes[](1);
internalCalls[0] = abi.encodeCall(IB20Security.updateShareRatio, (newRatio));

IB20Security(token).announce({
    internalCalls: internalCalls,
    id: "2026-Q3-split",
    description: "2-for-1 forward stock split",
    uri: "https://disclosures.example.com/..."
});
```

The four corporate-actions setters should be wrapped in `announce()`:

- `updateShareRatio(...)`
- `batchMint(...)`
- `batchBurn(...)`
- `updateSecurityIdentifier(...)`

Direct invocation by a role holder is permitted as an **emergency override** — it succeeds but produces no bracket events. Suitable only for break-glass scenarios where the inability to emit an announcement is itself part of the response.

## Batch Mint/Burn

`batchMint(recipients, amounts)` mints to many accounts in one call, gated by `MINT_ROLE`. `batchBurn(holders, amounts)` burns from many accounts in one call, gated by `BURN_FROM_ROLE`. Both should be wrapped in `announce()`, which additionally requires the operator to hold `SECURITY_OPERATOR_ROLE` (typically granted as a single bundle).

## Redemptions

Redemptions let token holders initiate their own burn — typically the on-chain leg of a flow where the issuer post-processes the redemption off-chain (delivering underlying assets, crediting fiat, etc.). The Security variant exposes `redeem(amount)` and `redeemWithMemo(amount, memo)`, both of which burn the caller's token balance and emit `Redeemed(redeemer, tokenAmount, shareAmount)`. `redeemWithMemo` additionally emits `Memo` per the indexer-join convention (see [B20 README → Memos](README.md#memos)).

Two gates apply on every call:

- `REDEEM_SENDER_POLICY` — the caller must be authorized.
- `minimumRedeemable` — admin-set floor (in shares); redemptions below this floor revert with `BelowMinimumRedeemable`. Any redemption that resolves to zero shares (e.g. token dust against a large share ratio) is always rejected, even when `minimumRedeemable == 0`. Read with `minimumRedeemable()`; update with `updateMinimumRedeemable(newMin)` (admin-gated; emits `MinimumRedeemableUpdated`).

> ⚠️ **`REDEEM_SENDER_POLICY` defaults to `ALWAYS_BLOCK` at token creation** — redemptions are closed until the admin explicitly opens them via `updatePolicy`. The conservative default reflects that redemption is irreversible and regulator-sensitive.

## Security Identifiers

Each Security token can carry one or more standardized identifiers (ISIN, CUSIP, FIGI, SEDOL, etc.). Read with `securityIdentifier(type)`; the value is a `string`. ISIN is required at creation via `B20SecurityCreateParams.isin`; other identifiers are optional and added post-creation.

`updateSecurityIdentifier(type, value)` adds or updates an identifier and should be wrapped in `announce()`. Passing an empty `value` removes the entry. Unknown identifier types revert with `InvalidIdentifierType`.

## Additional roles

### `SECURITY_OPERATOR_ROLE`

Gates the four corporate-actions setters (`updateShareRatio`, `batchMint`, `batchBurn`, `updateSecurityIdentifier`) and the `announce` wrapper itself. Held separately from `DEFAULT_ADMIN_ROLE` so corporate-actions operators don't need full admin authority. Operationally paired with `METADATA_ROLE` — when granting one, you typically grant the other to the same address.

### `BURN_FROM_ROLE`

Gates `batchBurn`, which burns balances held by other accounts as part of an announced corporate action. Distinct from `BURN_ROLE` (caller burns their own balance) and `BURN_BLOCKED_ROLE` (sanctions-seizure against policy-blocked addresses) — three burn primitives serve three different operational scenarios.

## Fixed Decimals (6)

`decimals()` is hard-wired to `6`. The choice matches the precision used by popular real-world securities-platform integrations.
