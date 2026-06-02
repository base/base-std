# B20 Security

The Security variant of B20 — designed for tokenized securities. Everything in [B20/README.md](README.md) applies; this page covers the deltas only. See [`IB20Security`](../../src/interfaces/IB20Security.sol) for the full Solidity interface.

## Multiplier

Each account's stored balance is the **raw** balance. A uniform on-chain **multiplier** scales that raw balance into a derived **scaled** view that consumers display. The multiplier applies to all accounts equally, which lets issuers model corporate actions like splits or reverse-splits without rewriting individual balances — the shape is similar to wstETH wrapping stETH, where the stored unit is the unwrapped quantity and the derived unit is the rebased view.

Read the current multiplier with `multiplier()`; the value is in WAD precision (`1e18`, exposed as `WAD_PRECISION()`). `toScaledBalance(rawBalance)` converts a raw amount to its scaled view, `toRawBalance(scaledBalance)` is the reverse converter (integer-floored, so the round-trip can lose up to one ULP), and `scaledBalanceOf(account)` is a convenience over ERC-20's `balanceOf` that returns the same account's raw balance in its scaled form.

`updateMultiplier(newMultiplier)` updates the multiplier and should be wrapped in an announcement (see [Announcements](#announcements)).

## Announcements

Announcements are publicly viewable notifications posted by a token operator. They can represent anything the operator wants to create a record of and can be coupled with actual state changes on the token (updating the multiplier, batched mints/burns, updating identifiers, and so on).

### Event Topology

An announcement is delimited by a paired `Announcement(msg.sender, id, description, uri)` event (opens the bracket) and `EndAnnouncement(id)` event (closes it). Every state-changing call dispatched inside the bracket belongs to that announcement. A recursion guard prevents nesting, and each `id` is enforced unique forever (`AnnouncementIdAlreadyUsed`) so indexers can correlate brackets across transactions.

Indexers should treat every `Announcement` log as the start of exactly one bracket; effects between `Announcement` and `EndAnnouncement` belong to the announced action; effects emitted *without* a surrounding bracket are direct invocations and should be flagged as emergency overrides.

### Wrapping calls in announcements

Wrap a set of operations in a single announcement by calling `announce(internalCalls, id, description, uri)`. The function (gated by `SECURITY_OPERATOR_ROLE`) emits `Announcement`, dispatches each internal call via self-`delegatecall` (which preserves `msg.sender` so the inner role checks see the operator), then emits `EndAnnouncement`. Inner reverts are wrapped in `InternalCallFailed` rather than bubbled — replay the call directly to debug. Nested calls to `announce` revert with `AnnouncementInProgress`; calls shorter than 4 bytes revert with `InternalCallMalformed`.

```solidity
// Disclose and execute a 2-for-1 forward split atomically.
bytes[] memory internalCalls = new bytes[](1);
internalCalls[0] = abi.encodeCall(IB20Security.updateMultiplier, (newMultiplier));

IB20Security(token).announce({
    internalCalls: internalCalls,
    id: "2026-Q3-split",
    description: "2-for-1 forward stock split",
    uri: "https://disclosures.example.com/..."
});
```

The three corporate-actions setters should be wrapped in `announce()`:

- `updateMultiplier(...)`
- `batchMint(...)`
- `updateSecurityIdentifier(...)`

Direct invocation by a role holder is permitted as an **emergency override** — it succeeds but produces no bracket events. Suitable only for break-glass scenarios where the inability to emit an announcement is itself part of the response.

## Batch Mint

`batchMint(recipients, amounts)` mints to many accounts in one call, gated by `MINT_ROLE`. It should be wrapped in `announce()`, which additionally requires the operator to hold `SECURITY_OPERATOR_ROLE` (typically granted as a single bundle).

## Security Identifiers

Each Security token can carry one or more standardized identifiers (ISIN, CUSIP, FIGI, SEDOL, etc.). Read with `securityIdentifier(type)`; the value is a `string`. All identifiers are optional and added post-creation — the factory does not seed any identifier at token creation.

`updateSecurityIdentifier(type, value)` adds or updates an identifier and should be wrapped in `announce()`. Passing an empty `value` removes the entry. Unknown identifier types revert with `InvalidIdentifierType`.

## Additional roles

### `SECURITY_OPERATOR_ROLE`

Gates the three corporate-actions setters (`updateMultiplier`, `batchMint`, `updateSecurityIdentifier`) and the `announce` wrapper itself. Held separately from `DEFAULT_ADMIN_ROLE` so corporate-actions operators don't need full admin authority. Operationally paired with `METADATA_ROLE` — when granting one, you typically grant the other to the same address.

## Fixed Decimals (6)

`decimals()` is hard-wired to `6`. The choice matches the precision used by popular real-world securities-platform integrations.
