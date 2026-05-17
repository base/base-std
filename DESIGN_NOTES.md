# Design Notes & Open Questions

Decisions, rationale, and open questions for the v1 interfaces in
`src/interfaces/`. Two sections:

- **[Design Rationale](#design-rationale)**: settled decisions and the
  reasoning behind them. Read this before reviewing the code if you want
  the "why" before the "what."
- **[Open Questions](#open-questions)**: items still requiring input,
  flagged inline so you can scan and respond.

---

## Design Rationale

### Cross-cutting decisions

#### Capabilities bitfield (immutable feature flags)

Every B-20 token exposes an immutable `capabilities()` bitfield, set at
creation by the factory. Each bit corresponds to one optional feature.
Functions whose bit is unset revert with `FeatureDisabled`, regardless
of role state.

**Why this exists.** Role renunciation alone is not strong enough for
honest signaling. An issuer who claims "this token cannot be paused"
might have renounced `PAUSE_ROLE` today but kept `DEFAULT_ADMIN_ROLE`,
allowing them to grant `PAUSE_ROLE` to anyone tomorrow. An integrator
checking for non-pausability would have to recursively analyze the role
admin tree and the current admin holder to be sure. Capabilities collapse
this into one immutable read: if the bit is unset, the function reverts
forever, no exceptions.

The bitfield is immutable per token (set once, never changed). New
features ship as new bits in higher positions; bits are append-only
across versions and never repurposed.

**Bit ranges per variant** to avoid collisions across the variant ABIs:
- Default-token bits: `1 << 0` through `1 << 15`
- Security-token bits: `1 << 16` through `1 << 23`
- Stablecoin-token bits: `1 << 24` through `1 << 31`

This leaves headroom in each range for v2 / v3 additions.

#### Default IS Core (variant inheritance, no separate ICoreToken)

`IStablecoin` and `ISecurityToken` both extend `IDefaultToken` directly
as siblings. There is no separate `ICoreToken` interface. The Default
token IS the canonical "ERC-20 + memos + roles + permits + policy + pause
+ URI + supply cap" surface that every variant inherits.

**Why.** Predictable variant ABIs (every B-20 token has at least the
Default surface), no parallel interface to keep in sync, and the
practical observation that there is no realistic case where a B-20 token
would NOT want any of the Default features. Tokens that want to
permanently disable specific Default features use the capabilities
bitfield to opt out at creation.

#### Single source of truth for compliance: external Policy Registry

All B-20 tokens delegate transfer authorization to the policy engine
via `transferPolicyId`. There is no internal blocklist on the token
itself. Sanctions lists, KYC allowlists, jurisdiction restrictions, and
similar compliance rules all live in the policy registry as
whitelist/blacklist/compound policies.

**Why.** Composability across tokens (one Coinbase-managed sanctions
blacklist policy serves every stablecoin AND every security AND every
default token that opts in), single auditable source for compliance
state, and no duplication of mechanism. CCS uses an internal blocklist;
we deliberately diverge to centralize this.

#### Memos as sibling functions, not optional parameters

`transfer` / `transferWithMemo`, `mint` / `mintWithMemo`, `burn` /
`burnWithMemo` are paired. The non-memo variants are byte-for-byte
ERC-20 compatible. The `WithMemo` variants are B-20 extensions.

**Why not a single function with optional `bytes32 memo`?** ERC-20
selector compatibility. Existing wallets, indexers, and contracts that
call `transfer(address, uint256)` need to keep working without
modification. Adding an unused `bytes32` parameter changes the selector.
The sibling pair pattern preserves the ERC-20 selector for the
non-memo'd path and offers the memo'd alternative under a different
selector.

The non-memo'd Transfer event is ALSO emitted on memo'd transfers (so
ERC-20 indexers see all token movement) along with the additional
`TransferWithMemo` event for indexers that want the memo. Same pattern
for mint/burn.

#### No third-party dependencies

The repo does not import OpenZeppelin, Tempo, Solady, or any other
third-party library. Reference implementations are written from scratch.
The reasoning, captured in the README: it's too easy to absorb someone
else's interface decisions wholesale instead of reaching our own
opinions. We can read prior art freely; we just don't link it.

This means the reference implementations will reimplement things like
EIP-712, ECDSA, ERC-1271 dispatch, and OZ-style RBAC by hand. Treat
those as illustrative, not gas-optimal.

### Roles & Admin model

#### MINT_ROLE and BURN_ROLE are separate

`IDefaultToken` exposes `MINT_ROLE` and `BURN_ROLE` as distinct role
identifiers. Originally combined as `ISSUER_ROLE` (TIP-20 convention),
we split them after reading CDP Custom Stablecoin (CCS), which has
them separate.

**Why.** Operational separation of concerns: a treasury team might be
authorized to mint (issuance) without being able to burn (redemption is
a different process), and vice versa. Compromise of one role does not
compromise the other. The split costs essentially nothing on the
interface surface and gives genuine ops authority granularity. Tokens
that want unified mint+burn authority just grant both roles to the
same address.

`burnBlocked` (force-burn from policy-blocked addresses) is not part of
the Default surface — it is a periphery/variant concern. See
`Capabilities.sol` for the rationale.

#### PAUSE_ROLE and UNPAUSE_ROLE are separate

Same pattern as TIP-20. Pause authority can be delegated to a 24/7 ops
team for emergency response without granting unpause authority. Unpause
is typically a more deliberate action requiring senior sign-off.

#### ~~Two-step admin transfer with delay~~ [ROLLED BACK]

> **This design was considered but dropped.** The active model is
> simpler: `grantRole(DEFAULT_ADMIN_ROLE, ...)` and
> `revokeRole(DEFAULT_ADMIN_ROLE, ...)` work uniformly with no delay or
> two-step handshake. See `IDefaultToken.sol` lines 273–278 for the
> authoritative `@dev` note. No `defaultAdminDelay` parameter exists in
> the factory creation structs.

The original rationale for the two-step design is preserved below for
historical context.

`DEFAULT_ADMIN_ROLE` is the single most powerful role on a token. It
controls all other role assignments. An accidental transfer to a wrong
address (typo, key error, contract that can't accept) permanently
bricks all admin operations. To prevent this, we considered adopting
the OZ `AccessControlDefaultAdminRulesUpgradeable` pattern, also used
by CCS.

The proposed mechanism:
- Admin transfer would be a TWO-step process. The current admin calls
  `beginDefaultAdminTransfer(newAdmin)`, scheduling the transfer.
- The new admin must call `acceptDefaultAdminTransfer()` after a
  configurable `defaultAdminDelay` elapses.
- The current admin can `cancelDefaultAdminTransfer` at any time before
  acceptance.
- `grantRole(DEFAULT_ADMIN_ROLE, ...)` and `revokeRole(DEFAULT_ADMIN_ROLE, ...)`
  would REVERT — the only valid transfer path is the two-step flow.

The delay was intended to protect against key compromise: if an attacker
steals the admin key and schedules a transfer to themselves, the
legitimate admin has `defaultAdminDelay` seconds to detect it and call
`cancelDefaultAdminTransfer`. A `defaultAdminDelayIncreaseWait` floor
would prevent an admin from "instantly" extending the delay to trap a
rightful owner.

This design was rolled back in favor of uniform `grantRole`/`revokeRole`
semantics. The complexity of the two-step mechanism outweighed its
safety benefit for this surface.

#### User-defined roles supported

Beyond the named role identifiers, the generic `grantRole(bytes32, address)`
accepts any `bytes32` value. Issuers can compute their own role hashes
(`keccak256("MY_CUSTOM_ROLE")`) and use them for external integrations.
The token itself only checks the named roles internally; user-defined
roles have no built-in effect on token functions but can be consumed by
wrapper contracts.

### Stablecoin-specific design

#### Per-minter rate limiting (`STABLECOIN_MINT_RATE_LIMITED`)

The single most distinctive feature CCS has over a vanilla ERC-20.
Each address holding `MINT_ROLE` has an independent rate-limit
configuration: a maximum capacity that replenishes linearly over a
configurable interval. `mint` calls consume from the caller's
remaining capacity.

**Why this matters for stablecoins specifically:**
- **Risk management.** If a minter key is compromised, the blast radius
  is bounded by their configured rate limit, not the entire supply cap.
- **Multi-party governance.** Different minters can have different
  quotas reflecting different operational responsibilities (e.g. CDP
  team has $X/day; treasury has $Y/day).
- **Operational compliance.** Per-team minting budgets enforce
  business-process boundaries on chain.

Default tokens typically have one issuer or none, and don't need this.
That's why the bit lives in the stablecoin range, not the default range.

`grantMinterRoleWithLimit` is an atomic combo: grants `MINT_ROLE` and
configures the rate limit in one transaction. Avoids the race where a
freshly-granted minter has the role but no limit configured and reverts
on first mint attempt. Pattern from CCS.

`MINT_RATE_LIMIT_ROLE` is held separately from `DEFAULT_ADMIN_ROLE` so
the authority that GRANTS minter access can be distinct from the
authority that TUNES per-minter quotas.

#### ERC-3009 Transfer With Authorization (`STABLECOIN_AUTHORIZATIONS`)

Gasless and front-run-resistant transfers. The user signs an EIP-712
authorization off-chain; anyone (or specifically the recipient) submits
it on-chain. USDC has had this for years; it is essentially the price
of admission for stablecoins that want to be used in payment apps.

**Distinct from EIP-2612 permit:**
- Permit sets allowances; ERC-3009 directly executes transfers.
- Permit uses sequential nonces; ERC-3009 uses random 32-byte nonces
  so multiple authorizations can be in flight concurrently.
- Permit has no time-window beyond a deadline; ERC-3009 has both
  `validAfter` and `validBefore` for scheduled-payment use cases.
- ERC-3009's `receiveWithAuthorization` is front-run-resistant: only
  `to` can submit. Useful when the payer signs for a specific recipient
  and wants no relayer to be able to redirect.
- `cancelAuthorization` lets the signer void an unused authorization
  preemptively. Permit has no equivalent.

Both are useful, complementary primitives. We expose both.

#### Currency identifier

`currency()` is an immutable string set at creation, identifying the
reference asset the stablecoin tracks (USD, EUR, BTC, etc.). Useful for
DEX routing, fee categorization, and wallet display.

Convention follows ISO-4217 codes for fiat / commodity references and
asset symbols for non-ISO references. See the function's docstring for
the full convention.

#### Freeze vs. seize philosophy

CCS does NOT have a force-burn function. The strongest action against a
malicious holder is `blocklist`, which freezes the address's balance
without destroying it. This is the "freeze, never seize" philosophy.

Tangor / Coinbase Tokenized Securities DOES have force-burn (called
`burnBlocked` in our interface). Sanctions enforcement requires the
ability to actually destroy the balance, not just freeze it.

`BURN_BLOCKED` was removed from the Default capability surface — force-burn
is a periphery/variant concern (see `Capabilities.sol`). The distinction
between freeze and seize philosophies still matters at the preset level:
`STANDARD_STABLECOIN` defaults to freeze-only (CCS style), while
`STANDARD_EQUITY` supports seizure via variant-specific mechanisms
(Tangor style). Issuers who want force-burn capability must opt in at
creation through a variant that exposes it.

### Security-specific design

#### Three issuance paths: `create`, `adminMint`, and inherited `mint`

Securities have legally meaningful semantics around supply changes that
do not map cleanly to ERC-20's `mint`. We expose three issuance paths:

- **`create(address to, uint256 amount)`**: the standard compliance-
  friendly issuance path. Single-recipient, rate-limited per caller,
  policy-checked. Distinct from `mint` because the legal definition of
  "creation" of a security is operationally distinct from arbitrary
  supply changes.
- **`adminMint(announcementId, recipients[], amounts[])`**: cold-path
  batch mint with announcement coupling. Used for unusual or emergency
  issuance (stock dividend distribution, recapitalization, error
  correction).
- **Inherited `mint(address, uint256)`**: typically DISABLED on
  security tokens via setting `MINTABLE = false` in capabilities.
  Issuers use `create` and `adminMint` instead.

The `STANDARD_EQUITY` preset reflects this: `MINTABLE` and `BURNABLE`
are off; `SECURITY_CREATABLE` and `SECURITY_ADMIN_BATCH` are on.

#### User redemption (`redeem`)

A holder calls `redeem(amount)` to destroy their tokens in exchange
for off-chain settlement to their brokerage account. This is distinct
from `burn` because it's user-initiated AND it triggers an off-chain
commitment from the issuer.

Gated on a separate `redeemPolicyId` (see below).

#### Policy engine scope: TIP-403 + TIP-1015 parity, no callback or richer guards in v1

We considered four levels of policy sophistication for v1:

1. **Pure set membership** (TIP-403): WHITELIST, BLACKLIST.
2. **+ Compound policies** (TIP-1015): asymmetric sender / recipient /
   mint-recipient slots referencing simple policies.
3. **+ Callback policies**: a fourth policy type that defers the
   authorization decision to a designated contract via `staticcall`.
   Solves time-, oracle-, lockup-, jurisdiction-, attestation-based
   rules without bloating the precompile.
4. **+ Modular guards / hooks**: the Modular ERC20 vision. Per-operation
   guard arrays, custom storage per guard, etc.

We ship **Levels 1 + 2 only** in v1.

The case for adding callback (Level 3) was real (richer rules without
chain bloat, small interface delta). But the forward-compat argument is
weak: even if we reserved the `CALLBACK` enum value now, the actual
implementation requires a hardfork — same as just adding it later.
Enum extensions are backward-compatible (existing values keep their
meanings), so consumers don't break when callback is added in a future
hardfork. Conclusion: defer to a future hardfork if real demand
emerges.

The user-stories doc explicitly lists three types (allowlist, blocklist,
compound). Conner has consistently steered toward "fork Tempo cleanly."
Our v1 matches that exactly.

**Rules that v1 DOES NOT support and would need future work:**
- Per-tx amount limits (callback signature lacks the amount)
- Counterparty-dependent rules ("X can only send to Y")
- Anything depending on per-transfer context

For these, issuers wrap the precompile in a Solidity contract that does
the rich check before/after calling through to the registry. Standard
pattern; no chain change needed.

#### Brokerage allowlist via separate `redeemPolicyId`

Each security token holds two policy IDs:
- `transferPolicyId`: gates transfers and mints. Typically a compound
  policy (e.g. KYC'd recipients, sanctions-blacklisted senders).
- `redeemPolicyId`: gates `redeem` callers. Typically a simple
  whitelist of brokerage-verified accounts. Coinbase manages this list
  by being the policy admin in the registry.

**Why separate IDs?** Transfer-eligibility and redeem-eligibility are
different sets in practice. Retail can hold and trade a tokenized
security without being able to redeem to brokerage; redemption requires
KYC + brokerage account connection that not all holders have. Putting
both behind the same policy would force every holder to be brokerage-
verified.

#### Announcement coupling for metadata changes

Every state-changing operation that affects security identity (share
ratio updates, name/symbol changes, identifier updates, admin
mint/burn) must be paired with an `Announcement(id)` event emitted
earlier in the same transaction. The token enforces this via transient
storage at the implementation level.

**Why on-chain enforcement, not just off-chain audit policy?** Strong
audit-trail invariant: it is impossible for a security token to change
identity without simultaneously emitting an announcement. Indexers,
exchanges, and wallets can rely on the chain itself to guarantee this.
The cost is a small transient-storage write per call; the benefit is
that audit reconstruction is mechanical rather than requiring trust in
the issuer's operational discipline.

Per the user-stories doc, the announcement URI itself is event-only
(not stored on-chain). Indexers must scan event logs to retrieve URIs
for a given announcement.

#### Share ratio for split-safe accounting

A security token's underlying ERC-20 balance is the "raw" balance.
Holders' "share" count is `balance * denominator / numerator`. Stock
splits and reverse splits change the ratio; raw balances NEVER change.

**Why.** A naive stock-split implementation that mints additional
tokens to every holder would break every smart contract that holds
the token (lending pools, AMMs, bridges, vaults) because those
contracts only know their deposit amount, not the post-split share
count. The ratio approach keeps raw balances stable so every smart
contract holder remains correct without modification; only the
displayed share count changes.

Wallets and integrators call `sharesOf(account)` instead of
`balanceOf(account)` for display purposes.

---

## Open Questions

Items below need your input. Status legend:
- 🟡 **OPEN**: needs decision
- ✅ **RESOLVED**: confirmed and reflected in current code; kept for context
- 🔴 **VERIFY**: ambiguity in source docs; resolved one way but worth confirming

### IDefaultToken

#### 🟡 OPEN: Should there be a `MEMOS_REQUIRED` capability bit?

Use case: a stablecoin issuer wants every transfer / mint / burn to
carry a non-zero memo for off-chain audit trail. With the bit set, the
non-memo'd `transfer` / `mint` / `burn` revert with `FeatureDisabled`.

Cost: one extra capability bit, one extra runtime check on each
non-memo path.

My lean: **add it**. Bit is cheap; it would be painful to add later.
Suggested bit position: `1 << 8`. Not added in current draft.

#### ✅ RESOLVED: `renounceRole` exempt from `ADMIN_MUTABLE`

Even on a token with `ADMIN_MUTABLE` off, role holders can voluntarily
renounce. For `DEFAULT_ADMIN_ROLE`, renunciation is scheduled through
the same two-step delay mechanism (with `newAdmin == address(0)`).

#### ✅ RESOLVED: Default `transferPolicyId = 1` (always-allow)

Default tokens default to always-allow at creation; security tokens
default to always-reject (paranoid) per their own surface (factory
parameter). Reflected in design intent; not yet enforced by interface
since defaults live in the impl/factory.

#### 🔴 VERIFY: Pause does NOT block mints/burns/admin actions

User stories doc is explicit; I went with that. Tangor's `pausedBurn`
function (which bypasses pause for admin burns) suggests they had a
"pause blocks everything" model and needed an escape hatch. Worth
confirming with Conner that the user-stories interpretation is the
intended one.

### Capabilities

#### 🟡 OPEN: Are `STANDARD_EQUITY`, `STANDARD_STABLECOIN`, `FIXED_SUPPLY` the right preset names / contents?

Preset values:
- `STANDARD_STABLECOIN` includes per-minter rate limiting and ERC-3009;
  defaults to freeze-only (CCS-style, no force-burn).
- `STANDARD_EQUITY` includes sanctions enforcement via variant-specific
  mechanisms (Tangor-style) and the security-specific bits.
- `FIXED_SUPPLY` is for default tokens with one-shot issuance.

Worth verifying these match what real issuers (CCS, Tangor, Coinbase
Wrapped Assets) would actually want.

### IStablecoin

#### ✅ RESOLVED: Per-minter rate limiting added

Reflects CCS pattern. `MINT_RATE_LIMIT_ROLE` configures, `MINT_ROLE`
mints. `grantMinterRoleWithLimit` atomic helper avoids first-mint
race.

#### ✅ RESOLVED: ERC-3009 added

Full surface (transfer, receive, cancel) with both ECDSA and ERC-1271
sig variants.

#### 🟡 OPEN: Reserve attestation accessor?

Could add `reserveURI() returns (string)` for proof-of-reserves data,
or rely on contractURI's off-chain JSON. Not added in current draft.

#### 🟡 OPEN: Yield distribution / rebase?

For yield-bearing stablecoins like Base USD's planned design. Mechanics
are complex (rebase storage, snapshot timing, indexer compatibility).
Defer to dedicated design pass; not added.

### ISecurityToken

#### ✅ RESOLVED: `redeemPolicyId` separate from `transferPolicyId`

Per the architectural recommendation. Brokerage allowlist managed via
the policy registry (Coinbase as policy admin).

#### ✅ RESOLVED: Per-caller create rate limit configured via `DEFAULT_ADMIN_ROLE`

Adopted the Tangor pattern (admin authority configures issuer quotas).
Could split out as `RATE_LIMIT_ADMIN_ROLE` later if needed.

#### 🔴 VERIFY: Announcement URI is event-only, not stored on-chain

User stories doc says event-only; wiki spec has on-chain getter. I
went with user stories. Indexers must scan logs to retrieve URIs.

#### 🟡 OPEN: Should `Announcement` event index `id` for filterability?

Currently `caller` is indexed; `id` is not. Indexers filtering by raw
string `id` would benefit from a separate `bytes32 indexed idHash`
field. Not added; flag if wanted.

#### 🟡 OPEN: `adminMint` / `adminBurn` should accept `totalAmount` parameter for sum validation?

Tangor's batch operations validate `totalAmount` matches the sum of
allocations. I omitted from current draft. Adds defense-in-depth
against caller-side off-by-one bugs at the cost of one extra parameter.

#### 🟡 OPEN: `adminBurn` can affect any account (not just policy-blocked) given announcement coupling

Powerful primitive: anyone with the appropriate burn role + a posted
announcement can destroy any holder's balance. Use cases for
non-blocked accounts: liquidations, reverse tender settlements,
accounting corrections. Worth explicit confirmation.

#### 🟡 OPEN: `share ratio` initial value at creation

Tangor uses `1_000_000_000 / 1_000_000_000` (large 1:1, fractional
headroom). Wiki spec uses `1 / 1`. Factory/impl decision; not in
interface. My lean: 1:1.

#### 🟡 OPEN: `pausedBurn` separate function vs. `adminBurn` always bypassing pause?

Tangor has a separate `pausedBurn`. Current design: `adminBurn` always
bypasses pause. Simpler but less explicit about the "this is intended
to operate during pause" semantic.

---

## What's NOT done yet

1. **Reference Solidity implementations** of all three token variants
   plus the factory and registry (`DefaultToken.sol`, `Stablecoin.sol`,
   `SecurityToken.sol`, `TokenFactory.sol`, `PolicyRegistry.sol`).
   Will be the biggest files in the repo.

2. **`StdPrecompiles.sol`** equivalent — constants for the policy
   registry, factory, and per-variant token address prefixes (TBD
   addresses).

---

## Notes on ITokenFactory unilateral choices

A few non-obvious things I picked while drafting that you should react
to:

### Per-variant deterministic address scheme

`(variant, creator, salt) → address`. Variant is encoded in the address
prefix so `variantOf(token)` is a pure address-shape decode, no SLOAD.
Implies we reserve three address prefix ranges (one per variant) at
the chain config level. Specific prefix bytes are TBD; the interface
just promises determinism + variant-recoverability.

### Initial supply mints bypass policy and capability checks

For Default and Stablecoin, `initialSupply` is minted to
`initialSupplyRecipient` atomically at creation. This bypasses BOTH
the policy check (the recipient does not need to satisfy
`isAuthorizedMintRecipient` on `transferPolicyId`) AND the `MINTABLE`
capability check (the bootstrap mint works even on a token where
`MINTABLE = false`).

Rationale: the policy and capability checks govern ongoing operation;
the initial mint is a one-time bootstrap configured by the creator
who is taking responsibility for the initial allocation. This makes
"fixed-supply meme coin" easy to express (set `MINTABLE = false`,
mint 1B at creation, done) without requiring temporary capability
gymnastics.

If you'd rather have the initial mint go through the same checks as
runtime mints, easy to flip. Worth thinking about.

### Security tokens have NO `initialSupply` parameter

Security tokens use `create` (rate-limited) and `adminMint` (cold-path
batch with announcement coupling) for issuance. Bootstrap flow is:

1. Factory creates the security token with no supply.
2. Admin configures the create() rate limit for one or more issuers
   via `configureCreateRateLimit`.
3. Issuers call `create()` to mint to allocation recipients.

Or the admin can use `adminMint` for a one-shot batch mint with an
announcement. Either path works; both produce more audit-trail than a
silent bootstrap mint.

### ~~`defaultAdminDelay` configurable at creation~~ [ROLLED BACK]

> **This factory parameter was part of the two-step admin transfer
> design, which was dropped.** No `defaultAdminDelay` field appears in
> any creation parameter struct. See the rolled-back section above and
> `IDefaultToken.sol` lines 273–278.

~~Each token's two-step admin transfer delay is set per-token at
creation via `defaultAdminDelay`. Different tokens can have different
delays based on their security posture (a stablecoin might want hours;
a memecoin might want zero). Admin can change later via
`changeDefaultAdminDelay` if the token's `ADMIN_MUTABLE` capability
is on.~~

### `predict*Address` does not depend on params other than `(creator, salt)`

The predicted address is stable across changes to name / symbol /
admin / capabilities / etc. — only `(variant, creator, salt)`
contributes. This lets callers compute the address before deciding
all the params, and lets pre-funding flows work without committing
to params upfront.

### Factory is permissionless

Anyone can call any create method. There is no `DEPLOYER_ROLE` or
similar; the factory itself has no admin. Each created token has its
own independent admin and is fully self-governing thereafter.

---

## Summary of bits I want explicit confirmation on

After your "yes to all" on the CCS-derived additions, the remaining
items needing your input:

1. `MEMOS_REQUIRED` capability bit — add now or defer? (My lean: add)
2. Preset contents (`STANDARD_STABLECOIN`, `STANDARD_EQUITY`,
   `FIXED_SUPPLY`) — confirm reasonable defaults?
3. Reserve attestation accessor on IStablecoin — add or defer to
   off-chain JSON?
4. Indexed `bytes32 idHash` on `Announcement` event — add for
   filterability?
5. `adminMint` / `adminBurn` `totalAmount` parameter for sum
   validation — add?
6. `adminBurn` semantics — confirm it can affect any account (gated by
   the burn role + announcement coupling), NOT restricted to
   policy-blocked addresses?
7. `share ratio` default at creation — 1:1 or 1e9:1e9?
8. `pausedBurn` as a separate function vs. `adminBurn` always
   bypassing pause?
9. The pause-doesn't-block-mints/burns interpretation (per user
   stories) — confirm?

Once you weigh in, I'll iterate the interfaces, then write
`ITokenFactory` + `IPolicyRegistry`, then start on reference impls.
