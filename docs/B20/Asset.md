# B20 Asset

The Asset variant of B20 — designed for assets of all kinds. Everything in [B20/README.md](README.md) applies; this page covers the deltas only. See [`IB20Asset`](../../src/interfaces/IB20Asset.sol) for the full Solidity interface.

## Multiplier

Each account's stored balance is the **raw** balance. A uniform on-chain **multiplier** scales that raw balance into a derived **scaled** view that consumers display. The multiplier applies to all accounts equally, which lets issuers rebase every balance at once — without rewriting individual balances — the shape is similar to wstETH wrapping stETH, where the stored unit is the unwrapped quantity and the derived unit is the rebased view.

Read the current multiplier with `multiplier()`; the value is in WAD precision (`1e18`, exposed as `WAD_PRECISION()`). `toScaledBalance(rawBalance)` converts a raw amount to its scaled view, `toRawBalance(scaledBalance)` is the reverse converter (integer-floored, so the round-trip can lose up to one ULP), and `scaledBalanceOf(account)` is a convenience over ERC-20's `balanceOf` that returns the same account's raw balance in its scaled form.

`updateMultiplier(newMultiplier)` updates the multiplier and should be wrapped in an announcement (see [Announcements](#announcements)).

## Announcements

Announcements are publicly viewable notifications posted by a token operator. They can represent anything the operator wants to create a record of and can be coupled with actual state changes on the token (updating the multiplier, batched mints, and so on).

### Event Topology

An announcement is delimited by a paired `Announcement(msg.sender, id, description, uri)` event (opens the bracket) and `EndAnnouncement(id)` event (closes it). Every state-changing call dispatched inside the bracket belongs to that announcement. A recursion guard prevents nesting, and each `id` is enforced unique forever (`AnnouncementIdAlreadyUsed`) so indexers can correlate brackets across transactions.

Indexers should treat every `Announcement` log as the start of exactly one bracket; effects between `Announcement` and `EndAnnouncement` belong to the announced action; effects emitted *without* a surrounding bracket are direct invocations and should be flagged as emergency overrides.

### Wrapping calls in announcements

Wrap a set of operations in a single announcement by calling `announce(internalCalls, id, description, uri)`. The function (gated by `OPERATOR_ROLE`) emits `Announcement`, dispatches each internal call via self-`delegatecall` (which preserves `msg.sender` so the inner role checks see the operator), then emits `EndAnnouncement`. Inner reverts are wrapped in `InternalCallFailed` rather than bubbled — replay the call directly to debug. Nested calls to `announce` revert with `AnnouncementInProgress`; calls shorter than 4 bytes revert with `InternalCallMalformed`.

```solidity
// Disclose and apply a community-ratified rebase atomically.
bytes[] memory internalCalls = new bytes[](1);
internalCalls[0] = abi.encodeCall(IB20Asset.updateMultiplier, (newMultiplier));

IB20Asset(token).announce({
    internalCalls: internalCalls,
    id: "2026-Q3-rebase",
    description: "Community governance proposal #42: ratified rebase",
    uri: "https://disclosures.example.com/..."
});
```

## Batch Mint

`batchMint(recipients, amounts)` mints to many accounts in one call, gated by `MINT_ROLE`. It should be wrapped in `announce()`, which additionally requires the operator to hold `OPERATOR_ROLE` (typically granted as a single bundle).

## Extra Metadata

Each Asset token can carry an arbitrary set of named metadata entries — a general-purpose key/value store the issuer is free to use however they want (e.g. `"category"` → `"electronics"`, `"region"` → `"north-america"`, `"reference"` → `"REF-2024-001"`). Read with `extraMetadata(key)`; the value is a `string`. All entries are optional and added post-creation — the factory does not seed any entry at token creation.

`updateExtraMetadata(key, value)` adds, updates, or removes an entry, gated by `METADATA_ROLE` (the same role that gates `updateName` / `updateSymbol`). It does NOT require `OPERATOR_ROLE` and can be invoked directly without an `announce()` wrapper. Passing an empty `value` removes the entry. An empty `key` reverts with `InvalidMetadataKey`.

## Additional roles

### `OPERATOR_ROLE`

Gates the `updateMultiplier` and the `announce`. These are metadata-like operations — they post disclosures and rescale the displayed balance rather than moving raw balances directly — but a compromised operator carries materially higher severity than ordinary metadata edits, so the capability is elevated into its own independent role instead of being folded into `METADATA_ROLE`. Held separately from `DEFAULT_ADMIN_ROLE` so operators don't need full admin authority.

## Configurable Decimals

`decimals()` is chosen at creation via `B20AssetCreateParams.decimals` and immutable thereafter. The factory enforces the inclusive range `[6, 18]` (exposed as `B20Constants.MIN_ASSET_DECIMALS` and `MAX_ASSET_DECIMALS`); out-of-range values revert `InvalidDecimals(decimals)`. `6` is the smallest unit any asset should use and `18` is a reasonable ceiling that encompasses the supermajority of assets.
