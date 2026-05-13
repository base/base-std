# Design Notes & Open Questions

Decisions, assumptions, and open questions accumulated while drafting the
v1 interfaces in `src/interfaces/`. Each item here is something to either
confirm with the team, defer to a follow-up, or change before this branch
gets pushed.

Organized by file + topic. Items marked **OPEN** need your input. Items
marked **ASSUMED** are decisions I made unilaterally; flag any you want
to revisit. Items marked **VERIFY** flag ambiguity in the source docs
that I want to disambiguate before going further.

---

## IDefaultToken.sol

### ASSUMED: `renounceRole` is exempt from `ADMIN_MUTABLE`

Even on a token with `ADMIN_MUTABLE` off, role holders can voluntarily
renounce their own role. Rationale: this is the only way for a freshly
deployed memecoin (with admin role granted to deployer for setup) to
truly reach a no-admin state. Renunciation is always defensive (you can
only revoke yourself), so it's safe to allow.

If you'd rather make `renounceRole` ALSO gated by `ADMIN_MUTABLE` (so
that an immutable token with an admin role granted at creation keeps
that admin forever), trivial change.

### ASSUMED: Default `transferPolicyId = 1` (always-allow), not 0 (always-reject)

A Default token should "just work" out of the box. Setting policy to
always-reject by default would break naive integrators.

The wiki `ISecurityToken` spec defaults to `transferPolicyId = 0`
(paranoid by default for securities). Matches my intuition: security
tokens should NOT transfer until the issuer explicitly configures
compliance.

So **OPEN**: do we default `ISecurityToken` to `transferPolicyId = 0`
at creation (overriding the IDefaultToken default of 1)? My lean: yes,
and the security factory's `createSecurity` method should require an
explicit policy ID at creation rather than letting it default.

### ASSUMED: Permit overload with `bytes signature` accepts BOTH EOA and contract owners

The `(v, r, s)` form is the canonical EIP-2612 path for EOA owners. The
`bytes signature` form is the new ERC-1271-compat path. I made the
`bytes` form accept both: if `owner.code.length == 0`, treat the bytes
as 65-byte packed `(r, s, v)`; otherwise call ERC-1271. Means callers
don't need to pre-check the owner's code state.

If you'd prefer strict separation (the bytes form is contract-only,
EOAs MUST use the `(v, r, s)` form), small change.

### OPEN: Should there be a `MEMOS_REQUIRED` capability bit?

You were unsure. Use case: a stablecoin issuer (or institutional
default-token issuer) wants every transfer / mint / burn to carry a
non-zero memo for off-chain audit trail. With the bit set, the
non-memo'd functions revert with `FeatureDisabled`.

Cost: one extra capability bit, one extra runtime check on each
non-memo path.

My lean: **add it now**. Bit is cheap, and it's the kind of thing that
would be painful to add later for a hypothetical compliance-required
issuer. Suggested bit: `1 << 8`. Not added in current draft; flag if
you want it.

### ASSUMED: Both `Transfer` (ERC-20) AND custom events emitted on every operation

A memo'd transfer emits BOTH `Transfer(from, to, amount)` AND
`TransferWithMemo(from, to, amount, memo)`. Mints emit BOTH
`Transfer(0, to, amount)` AND `Mint(to, amount)`. Etc.

Slight redundancy in event log gas cost (~750 gas per extra topic) but
preserves indexer compatibility: anything listening for ERC-20 Transfer
events sees all token movement.

If you'd rather skip the extra event when the memo'd path is taken (so
a memo'd transfer emits ONLY `TransferWithMemo`, not `Transfer`),
slight change. But that breaks ERC-20 indexer compat.

### VERIFY: The user stories doc says "Pausing prevents transfers. Pausing does not prevent mints, burns, and token configuration changes."

I implemented this exactly. It's a deviation from typical OpenZeppelin
`Pausable` semantics where pause blocks ALL state changes. The user
stories are explicit so I went with the user stories interpretation.

Worth confirming with Conner that this is intentional. The Tangor
reference impl on `feat/commodity` has its own carve-out (`pausedBurn`
function explicitly bypasses pause for admin burns), suggesting the
"pause blocks everything" model needed escape hatches.

---

## Capabilities.sol

### ASSUMED: Bit number ranges per variant

- Default token bits: `1 << 0` through `1 << 15` (8 used, 8 reserved)
- Security token bits: `1 << 16` through `1 << 23` (5 used, 3 reserved)
- Stablecoin bits (when added): I'd suggest `1 << 24` through `1 << 31`

This keeps each variant in its own well-defined range. Append-only
within ranges (never re-purpose a published bit). Lots of headroom in
each range; we'll never run out.

### OPEN: Should `BURN_BLOCKED` be its own bit, or folded into `BURNABLE`?

You said "not sure yet." I split them. Rationale: a memecoin issuer
might want general `burn` permanently disabled (fixed supply) but want
`burnBlocked` enabled for sanctions enforcement. Or the opposite: open
self-burn but no force-burns ever. Splitting captures both.

Cost: one extra bit. Trivial.

If you'd rather merge them, fold `BURN_BLOCKED` semantics into
`BURNABLE` and remove the bit. Easy change.

### OPEN: Are `STANDARD_EQUITY` and `FIXED_SUPPLY` the right preset names / contents?

I added `STANDARD_EQUITY` as a preset for security tokens that's the
"everything except inherited mint/burn" combo. It's long and I don't
love the name. Alternatives:

- `EQUITY_DEFAULT`
- `FULL_EQUITY`
- Drop the preset entirely and let the security factory have a default

The `FIXED_SUPPLY` preset (PAUSABLE | ADMIN_MUTABLE | POLICY_MUTABLE |
URI_MUTABLE) is for default tokens with one-shot issuance. Worth
verifying this matches what an issuer like Coinbase Wrapped Assets
would actually want.

---

## IStablecoin.sol

### ASSUMED: Stablecoin variant adds ONLY `currency()` for v1

You said "I think there's probably more stuff" but didn't enumerate.
Without CDP Custom Stablecoin access yet, I went minimal: one
addition. Leaves room to grow without breaking anything.

The single addition (`currency()`) is genuinely stablecoin-specific
and well-justified by Tempo precedent + DEX/routing utility.

### OPEN: What else should IStablecoin add?

Candidates I considered and deferred, ranked by my read of importance:

1. **Reserve attestation accessor.** `function reserveURI() external
   view returns (string memory);` — pointer to off-chain
   proof-of-reserves data. Useful for transparent-reserve stablecoins.
   Could also live in the contract URI's off-chain JSON, so maybe not
   needed as a dedicated function. **Worth discussing.**

2. **Master Minter pattern (Circle-style).** Two-tier role structure:
   `MASTER_MINTER_ROLE` can grant per-minter allowances; `MINTER`s
   have quota that depletes as they mint. Significant addition (~5
   functions, per-minter state). Not in user stories. **Defer to v2
   unless Tangor / CCS explicitly need it.**

3. **Per-account `freeze` / `unfreeze`.** Distinct from burn-blocked:
   freeze stops an account from sending without destroying their
   balance, useful for compliance investigations. Could be done via a
   compound policy with a sender-blacklist instead, so probably
   redundant with the policy engine. **Skip.**

4. **Yield distribution (auto-rebase or manual).** For yield-bearing
   stablecoins like Base USD's planned design. The mechanics are
   complex (rebase storage, snapshot timing, indexer compatibility).
   **Significant work; defer to dedicated design pass.**

I would NOT add any of these without explicit user-story sign-off.
Want me to draft any of them as proposals?

---

## ISecurityToken.sol

### ASSUMED: Security tokens disable inherited `mint` / `burn` via capability bits

The user stories distinguish "Mint and Burn" (Core, requires ISSUER_ROLE)
from "Create" (Security, rate-limited compliant path) and "Admin Mint"
(Security, cold-path batch with announcement coupling). I read this as:
security tokens shouldn't expose the inherited single-account `mint` /
`burn` from IDefaultToken; they should use `create` and `adminMint` /
`adminBurn` instead.

So a security token typically has:
- `MINTABLE = false` (inherited `mint` reverts)
- `BURNABLE = false` (inherited `burn` reverts)
- `BURN_BLOCKED = true` (sanctions enforcement)
- `SECURITY_CREATABLE = true` (compliant issuance via `create`)
- `SECURITY_ADMIN_BATCH = true` (cold-path `adminMint` / `adminBurn`)
- `SECURITY_REDEEMABLE = true` (user-side `redeem`)

**This is reflected in the `STANDARD_EQUITY` preset.**

If you'd rather have security tokens KEEP `mint` / `burn` inherited
(with stricter behavior — e.g., add announcement coupling at the impl
level), the interface stays the same; just flip the recommended bits.
But I think the "use the security-specific names" approach is clearer
for integrators.

### OPEN: `redeem` brokerage allowlist as a separate `redeemPolicyId`

I went with this from the previous conversation: each security token
has a `redeemPolicyId` (separate from `transferPolicyId`) pointing at
a policy registry whitelist. Coinbase manages the allowlist by being
the admin of that policyId.

Two design implications worth confirming:

1. **`redeemPolicyId` is a single uint64 in token state, mutable by
   admin.** I added `redeemPolicyId()` getter and
   `setRedeemPolicyId(uint64)` setter. The setter is gated by
   `DEFAULT_ADMIN_ROLE` only; I did NOT add a `REDEEM_POLICY_MUTABLE`
   capability bit because I figured this is a critical operational
   lever the issuer should always be able to update. Confirm.

2. **What happens if `redeemPolicyId == 0` (always-reject)?** Then
   nobody can redeem. That's the safest default for newly created
   securities — the issuer must explicitly set a policy when ready.

### ASSUMED: Per-caller create rate limit is a simple `(maxAmount, interval)` pair

`createAllowance(caller)` returns the remaining quota; allowance
replenishes linearly over `interval`. This matches Tangor's
`RateLimit` mixin shape.

Open detail: how is this configured? I exposed
`configureCreateRateLimit(caller, maxAmount, interval)` gated by
`DEFAULT_ADMIN_ROLE`. So the admin sets per-issuer quotas. Confirm
that's the right authority (vs. e.g. a separate `RATE_LIMIT_ADMIN_ROLE`).

### VERIFY: Announcement URI storage — on-chain or event-only?

The user stories say:
> "We don't store, announcement URI's on contract, just annotated on events"

The wiki `ISecurityToken` spec says:
> `function announcementURI(string id) external view returns (string memory);`

These contradict. **I followed the user stories** (no on-chain URI
storage; URI lives in event only) since it's the more recent / active
working doc. So my interface has NO `announcementURI` view function.

Implication: indexers need to scan event logs to retrieve the URI for
a given announcement; not directly queryable from contract storage.

If we want on-chain queryability, add the storage and the getter and
add the URI to a per-token mapping. Not a hard change; just a tradeoff
between gas (write the URI to storage) vs. integration friction (need
an indexer to fetch).

### OPEN: Should `Announcement` event index `id`?

I made `caller` indexed but `id` and other fields not indexed. If
indexers commonly want to filter by `id`, indexing it would help. But
`id` is a string and Solidity indexes strings as their hash, which
makes indexer-side filtering by raw string value awkward.

If you want to filter by `id`, the convention is to make a separate
indexed field that's the keccak hash of the id. Could change to:
```solidity
event Announcement(address indexed caller, bytes32 indexed idHash, string id, string description, string uri);
```

Not in current draft. Flag if wanted.

### OPEN: Atomic vs. partial-success semantics on `adminMint` / `adminBurn`

Tangor's batch operations validate `totalAmount` matches the sum of
allocations and revert atomically on any failure. I documented "reverts
atomically if any single recipient fails" in the docstrings but didn't
add a `totalAmount` parameter to the function signature. Should I?

Pros of `totalAmount`: catches caller-side bugs (off-by-one in batch
construction) at the contract layer rather than discovering after a
partial mint.

Cons: extra parameter, slight gas, redundant with validation the
caller already did (presumably).

My lean: omit. The atomic-revert behavior is documented; the caller
can compute their own total client-side. But Tangor includes it, so
maybe consistency with their pattern is preferable.

### OPEN: Should `adminBurn` also work for general account burns, not just sanctions?

Right now I have:
- `burnBlocked(from, amount)` — inherited from IDefaultToken; force-burn
  from a policy-blocked address.
- `adminBurn(announcementId, accounts[], amounts[])` — cold-path batch
  burn from any account, requires announcement.

These overlap. `adminBurn` could be used to seize from a
non-policy-blocked address (since it doesn't check the policy). Is
that a feature or a bug?

Use case for `adminBurn` on non-blocked addresses: liquidations,
reverse tender offers, accounting corrections. These are legitimate.
But it's a powerful primitive — anyone with `BURN_BLOCKED_ROLE` can
destroy any holder's balance with an announcement.

My lean: **leave it as documented** (adminBurn can affect any account
with announcement coupling). The role gate is the security boundary.
The announcement provides the audit trail. Confirm with you / Conner.

### OPEN: `share ratio` initialization

The interface assumes a security token starts with some share ratio.
What's the default at creation if the issuer doesn't specify? Tangor
uses `1_000_000_000 / 1_000_000_000` (a large 1:1 to give headroom for
fractional updates without precision loss). The wiki spec uses `1 / 1`.

My interface doesn't take a position; this is a factory/impl decision.
Worth flagging because the choice affects how splits work numerically.
My lean: **use 1:1 default, big numbers only when needed**. Simpler
mental model.

### OPEN: `pausedBurn` — separate function or a flag on `adminBurn`?

User stories: "Admin Burn ... Can burn when paused." I made `adminBurn`
*always* bypass the pause check (even when not paused, it just doesn't
look at pause state). Alternative: have `pausedBurn` as a separate
function that can ONLY be called when paused.

Tangor does the latter (separate `pausedBurn`). I went with the former
for simplicity. If you prefer Tangor's pattern, add a separate
`pausedBurn` function and remove the pause-bypass from `adminBurn`.

---

## What's NOT done yet

1. **`ITokenFactory.sol`** — the singular factory with three create
   methods. Each method takes a struct including `capabilities`,
   `initialSupply`, `policyId`, `name`/`symbol`/`decimals`, etc. I
   need your sign-off on the interfaces above before writing this; the
   factory's signature space is mostly determined by what each variant
   needs at creation time.

2. **`IPolicyRegistry.sol`** — the policy engine interface. Adapted
   from Tempo's TIP-403 + TIP-1015 with our additions (no virtual
   address rejection logic, no receive policies / TIP-1028 escrow
   integration). Will be its own commit.

3. **Reference Solidity implementations** of all three token variants
   (`DefaultToken.sol`, `Stablecoin.sol`, `SecurityToken.sol`,
   `TokenFactory.sol`, `PolicyRegistry.sol`). These will be the
   biggest files in the repo.

4. **`StdPrecompiles.sol`** equivalent — the constants file mapping
   precompile addresses for the policy registry, factory, and the
   per-variant token address prefixes (TBD addresses).

---

## Summary of bits I want explicit confirmation on

If you read nothing else, scan and give me a thumbs up / thumbs down
on these:

1. `MEMOS_REQUIRED` capability bit — add now or defer? (My lean: add)
2. `BURN_BLOCKED` as separate bit from `BURNABLE` — keep split or merge?
3. `IStablecoin` minimal (just `currency()`) for v1 — ok?
4. Security tokens default to `transferPolicyId = 0` at creation — ok?
5. `redeem` brokerage allowlist as separate `redeemPolicyId` per the
   recommendation from previous conversation — ok?
6. Announcement URI is event-only, not stored on-chain (per user stories) — ok?
7. `adminBurn` can affect any account (not just policy-blocked) given
   announcement coupling — ok?
8. Indexed `id` on `Announcement` event for filterability — add?
9. Per-caller create rate limit configured via `DEFAULT_ADMIN_ROLE` —
   ok or want a separate `RATE_LIMIT_ADMIN_ROLE`?

Once you weigh in, I'll iterate the interfaces, then write
`ITokenFactory` + `IPolicyRegistry`, then start on reference impls.
