# ITokenFactory Design Notes

Decisions and open questions for the B-20 token factory precompile. Pair
this with `src/interfaces/ITokenFactory.sol` for the full picture.

## Why no address prefix for B-20 tokens

Earlier drafts proposed reserving short address prefixes (e.g. `0xB200`
for Default / Stablecoin and `0xB201` for Security) so that
`variantOf(token)` could decode the variant from the address shape with
no storage read. **We rejected this in favor of a chain-level
registry** because of backward compatibility on Base.

### The math

- Base has roughly tens of millions of deployed contracts.
- A 16-bit prefix (e.g. `0xB200`) reserves `2^144` of the `2^160`
  address space, but that prefix is shared by `2^144` addresses, of
  which a uniform distribution of existing contracts puts roughly
  `10M / 65k ≈ 150-500` already-deployed Base contracts at addresses
  beginning with `0xB200`. Same again for `0xB201`.
- These are real, live contracts (DEX pools, NFT contracts, user
  wallets, anything).
- Reserving the prefix would either break those contracts (the chain
  starts dispatching their addresses to the B-20 precompile) or
  require a one-off scan + grandfathering at the hardfork.
- Longer prefixes (e.g. 64-bit) make collisions astronomically
  unlikely but still require chain-level coordination on which prefix
  bytes to reserve AND restrictions on user CREATE / CREATE2
  deployments into the reserved range.
- The simpler answer is to drop the prefix entirely.

### What we use instead

- B-20 tokens have arbitrary-looking addresses (CREATE2-style
  deterministic derivation from `(variant, creator, salt)` with no
  fixed prefix).
- The chain maintains an internal registry of "addresses that are B-20
  tokens", populated by this factory at creation time.
- Dispatch logic on every call: if the target address is in the
  registry → route to the B-20 precompile; else → normal EVM dispatch.
- `variantOf(token)` reads from that registry (one storage slot).

### What we give up

- `variantOf(token)` becomes a storage read instead of a pure address
  decode. Acceptable: it isn't called on every transfer, only on
  introspection.
- B-20 tokens have no visual marker in their address. Wallets and
  indexers that want to identify B-20 tokens consult the registry
  (or call `isB20(token)` on the factory).

### Sequencer optimization story is preserved

The sequencer can prefetch / cache the registry aggressively. The
"is this address a B-20 token?" check is still O(1) and entirely
predictable. We just use a registry lookup instead of an address-shape
decode.

## Resolved decisions

### Address derivation algorithm

Implementation detail; not specified at the interface level. Standard
CREATE2-style hash of `(variant derivation domain, creator, salt)`
producing a 20-byte address. **There is no fancy prefix scheme** (per
the address-prefix discussion above; we can't reserve prefixes on
Base). The Rust precompile implementation picks the exact derivation
function; what's locked at the interface level is determinism (`predict*Address`
returns the address `create*` would assign) and the variant-domain
separation (Default / Stablecoin share a domain; Security uses a
different domain).

### Capability bit validation at creation

Factory validates the capability bitfield at creation and reverts with
`InvalidCapabilities` if any bit is set that isn't valid for the chosen
variant. For Default and Stablecoin tokens, only `PAUSABLE` and
`CAP_MUTABLE` are currently valid. For Security tokens, the additional
security-specific bits in `Capabilities` (16..23 range) are also valid.

### `transferPolicyId` default at creation

Required at creation but no implicit default. Recommended values:

- **Pass `1` (always-allow)** for tokens that don't need compliance
  gating. This is the typical default for memecoins and similar.
- **Pass `0` (always-reject)** to start the token in a soft-paused
  state where transfers fail until the admin sets a real policy via
  `changeTransferPolicyId`. Useful when the policy isn't yet
  configured at creation.
- **Pass any existing custom policy ID** to apply that policy from
  creation.

The factory does not auto-default to `1` because we want the choice
to be explicit; passing `0` accidentally is a foot-gun (the token
would be silently unusable), so callers should know what they're
doing.

## Other decisions baked into the current draft

- **Three creation methods** (one per variant), not the unified
  `createToken(...variant...)` from the PRD. Diverges from PRD wording
  in favor of typed per-variant params; happy to revert if the team
  prefers the unified shape. (See open question #4 below.)
- **`TokenVariant` enum has no `STABLECOIN` value.** Stablecoin and
  Default share the same address derivation and the same `DEFAULT`
  variant marker. Sub-case is detected via `isStablecoin(token)` (which
  checks `currency() != ""`). (See open question #3 below.)
- **Default and Stablecoin share address space.** Same `(creator, salt)`
  pair maps to one token of either variant; calling `createDefault`
  precludes `createStablecoin` at the same slot and vice versa.
- **Security uses a different derivation domain.** Security tokens at
  the same `(creator, salt)` get a different address from Default /
  Stablecoin, so no collision risk across variants.
- **Per-token custom decimals** (and immutable after creation, per
  IDefaultToken).
- **`admin == address(0)` explicitly allowed** for the "demonstrate no
  owner" case from the PRD. Tokens with no admin: no role grants, no
  policy changes, no pauses. The last-admin-renounce guard in
  `IDefaultToken.renounceRole` does not apply because there was never
  an admin to renounce.
- **Initial supply bootstrap mint** for Default and Stablecoin (atomic
  with creation). Security tokens have no `initialSupply` (use
  `create` / `adminMint` after creation).
- **Permissionless creation.** Anyone deploys; no factory admin.
- **No wrapper coupling.** Factory creates the token only. Wrappers
  (Bridge's TIP20Controller, CCS's beacon proxy, etc.) deploy
  separately as normal EVM contracts.

## Open questions to take to the team

### 1. Bootstrap mint policy bypass vs apply

Current draft bypasses the transfer policy check on the initial mint at
creation (the policy referenced by `transferPolicyId` may legitimately
not authorize the recipient yet at creation). Argument for applying:
**fail-fast sanity check on setup**. If the issuer mints to an address
that the policy then can't authorize for transfers, that supply is
stuck and the token has to be redeployed. Catching this at creation is
nice. Argument against: **mint and transfer policies can differ**.
Compound policies have separate `senderPolicyId` and
`mintRecipientPolicyId` slots, so an address might legitimately be
authorized to receive mints but not to send transfers (or vice versa).
The bootstrap mint check should probably be against the
`mintRecipientPolicyId` slot specifically, not the full transfer check.

Lean: apply the `mintRecipientPolicyId` check at bootstrap. Keep open
pending team discussion on whether the friction is worth it.

### 2. Two-step "renounce last admin" pattern

Not in v1. The last-admin guard in `IDefaultToken.renounceRole`
prevents the LAST admin from renouncing, which means tokens cannot
evolve from admin-controlled to admin-less mid-life. Real use case:
**a token might need active admin oversight for an initial setup
period (mintable while bootstrapping, configuring policies, etc.) and
then need to renounce admin control once the setup is done**.

Lean: we probably need this. Mechanism would be a delay-protected
two-step renounce on `IDefaultToken` (something like
`beginRenounceLastAdmin` → wait → `acceptRenounceLastAdmin`). Worth a
separate design discussion before adding.

### 3. Drop `STABLECOIN` from the enum entirely vs keep it

Current draft drops it because Default and Stablecoin share both the
address derivation and the variant marker. Stablecoin is detected
via `isStablecoin(token)` (one external call into the token's
`currency()` accessor). Worth team confirmation that this collapse is
desirable.

### 4. Three separate functions vs one unified `createToken(variant, ...)`

PRD wording implies unified. Current draft uses separate per-variant
functions for clearer typing and per-variant params structs. Worth
team confirmation.
