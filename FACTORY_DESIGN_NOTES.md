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

## Other decisions baked into the current draft

- **Three creation methods** (one per variant), not the unified
  `createToken(...variant...)` from the PRD. Diverges from PRD wording
  in favor of typed per-variant params; happy to revert if the team
  prefers the unified shape.
- **`TokenVariant` enum has no `STABLECOIN` value.** Stablecoin and
  Default share the same address derivation and the same `DEFAULT`
  variant marker. Sub-case is detected via `isStablecoin(token)` (which
  checks `currency() != ""`).
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

1. **`transferPolicyId` required vs default.** Currently required to
   force an explicit compliance choice at creation. Tradeoff: more
   friction for memecoins / simple tokens that don't need compliance.
   Alternative: optional, defaults to policy ID `1` (always-allow).

2. **Bootstrap mint policy bypass vs apply.** Current draft bypasses
   the transfer policy check on the initial mint at creation (the
   policy referenced by `transferPolicyId` may not authorize the
   recipient yet). Alternative: require the policy to authorize the
   recipient at bootstrap, which is tighter but requires the policy
   to be created BEFORE the token (awkward chicken-and-egg).

3. **Two-step "renounce last admin" pattern.** Not in v1. The
   last-admin guard in `IDefaultToken` prevents the LAST admin from
   renouncing. Issuers who want to evolve from admin-controlled to
   admin-less mid-life have no clean path. Worth a separate design
   discussion.

4. **Drop `STABLECOIN` from the enum entirely vs keep it.** Current
   draft drops it because Default and Stablecoin share both the
   address derivation and the variant marker. Worth team confirmation.

5. **Three separate functions vs one unified `createToken(variant, ...)`.**
   PRD wording implies unified. Current draft uses separate per-variant
   functions for clearer typing and per-variant params structs. Worth
   team confirmation.

6. **Address derivation algorithm.** Implementation-level decision.
   Should be salt-domain-separated so that Default / Stablecoin and
   Security derivations are uniquely keyed even with the same
   `(creator, salt)` input. Lock down before reference impl.

7. **Capability bit validation at creation.** Factory should reject
   capability bitfields with bits not valid for the chosen variant
   (e.g. security-specific bits on a Default token). Straightforward
   but worth confirming the validation rules.
