# ADR Template (Point Form)

- **Feature Name**: seize
- **Start Date**: 2026-08-17
- **Authors**: Rayyan Alam
- **Title**: Seize surface + burnBlocked deprecation

> Fill in each section below when documenting a change. Pointform here can be sufficient

---

## Summary

> Give a summary of the change: who it's for, what it does.

- Add `seizeWithMemo` to the shared `IB20` interface — inherited by both B20 Asset and B20
  Stablecoin, no variant-specific logic
- Original flow to seize an asset was block + `burnBlocked` + mint (destroy then reissue);
  `seizeWithMemo` replaces this with a single admin call that reassigns the balance directly
- Ships at the **Cobalt** hardfork, which has not activated on-chain yet (README lists it
  `Upcoming`). Seize has no separate `ActivationRegistry` flag — it activates automatically at the
  Cobalt hardfork date (unlike `PolicyRegistry`'s composite policies, which need an explicit
  activation flip)
- **Compatibility promise**: `burnBlocked` remains fully dialable with its existing behavior —
  no removal is planned (permanent, not a phased deprecation; BOP-471, the re-merge ticket, was
  canceled). `seizeWithMemo` is new, additive surface; nothing existing is broken
- Audience: token issuers/compliance integrators currently using the block+burn+mint workaround,
  and anyone integrating against the deprecated `burnBlocked` path


---

## Motivation

> State the problem this change solves, why the current state is insufficient, and brief context
> on prerequisites if needed (full detail lives in Background).

- Compliant asset issuers need freeze+seize models. Today we achieve this with
  block+burnBlocked+mint (destroy then reissue). `seizeWithMemo` replaces that workaround with a
  direct balance reassignment (`from` → `to`) that neither burns nor mints — `totalSupply` is
  unchanged — and emits a single, purpose-built `Seized` event
- Burn functionality should be explicitly distinct from seize; they may be gated on different
  policies
- The current functionality is 3 step to sezie 
    - Configure `from` as blocked under `TRANSFER_SENDER_POLICY` (the same policy `burnBlocked`
      reads today — verified against `IB20.sol`)
    - Burn assets  --> Effectes token supply
    - Mint assets to seieze 
    - Emits a burn and a Mint
    - Does not indicate a seize occured
- Proposed functionlaity 
    - Add in policy to be seized from 
    - use the seizeWithMemo function --> emits seize event 

---

## Background

> Link to or summarize concepts the reader needs before understanding the Specs: prior art,
> relevant EIPs/ERCs, existing patterns, and any domain-specific terms used in this document.
- B20 Asset and B20 Stablecoin 
    - Natve token launched on B20
    - Has in built roles and acess controls
    - Functions are gated using policy registry and policy functionality
- Policy Registry
    - A singleton precompile contract, whose responsibility is to return `isAuthorized(policyId,
      account)` (verified against `IPolicyRegistry.sol` — not `isAllowed(address, true)`)
    - Used by B20, gating operations by passing the stored policy ID and the account to check
---

## Specs

> Implementation details live here. Add more headings as needed (e.g., Storage Layout Changes,
> Deprecated Assets, Access Control, etc.).

### Interface Changes

> New functions, events, errors (include signatures). Renamed or deprecated symbols (old → new).
> Selector / topic0 values.
    - Old → new mapping (selectors/topics verified via `cast sig`/`cast keccak` against
      `src/interfaces/IB20.sol` and `src/lib/B20Constants.sol`):
        - `burnBlocked(address,uint256)` `0xec0cf3dc` — **deprecated-dialable**, unchanged
          behavior, no removal date committed
        - `error AccountNotBlocked(address)` `0x64a5cb46` — unchanged, still exclusive to
          `burnBlocked`
        - `event BurnedBlocked(address,address,uint256)` topic0
          `0x0b552e96653fd6842da37c477005d3b5c08a8c7d3631b1f43787b2dc9a1006a3` — unchanged, still
          exclusive to `burnBlocked`
        - NEW `seizeWithMemo(address,address,uint256,bytes32)` `0xf916d81b` — single-call
          admin seize, reassigns `from`'s balance to `to`
        - NEW `SEIZE_ROLE()` `0x3c7e9ba5` (role value `0x3469b8b0d89e9604f8510ed143f74a8336d22955d4f83e23bf53d9414e27f432`)
        - NEW `SEIZE_HOLDER_POLICY()` `0xb279d311` (`0x1497ab2b67ebb0a75dd9cdd6aec9f0e64620e6b87e911af7a088ac12e58d9ef2`)
          — gates who is seizable; inverted membership (seizable if NOT authorized)
        - NEW `SEIZE_RECEIVER_POLICY()` `0xb31da27f` (`0xbf15b19caf5c77422c038bc25f26b8b815c3a14f6d04c6616076b81bcfe07b3d`)
          — gates seize destination; unset slot = always-allow
        - NEW `event Seized(address indexed caller, address indexed from, address indexed to, uint256 amount)`
          topic0 `0xa9aec5d8b86e2fa2fd6ac3af62f2622e3dfdab1967d4cbbb56a5df7d74cb887c`
        - NEW `error AccountNotSeizable(address)` `0x91dbbc8d`
        - NEW `PausableFeature.SEIZE` — dedicated pause vector, independent of `BURN`
    - All function/error selectors, event topic0s, and role/policy hash values above re-verified
      via `cast sig`/`cast keccak`/`cast sig-event` against `IB20.sol` and `B20Constants.sol` on
      2026-08-18
    
### Behavioural Changes

> How execution flow differs from the previous version. Storage layout changes (new slots, moved
> fields, packing changes). Gas cost implications if meaningful.
- `seizeWithMemo(from, to, amount, memo)` — verified exact guard/emission order, per
  `MockB20.sol`'s reference implementation and `IB20.sol`'s natspec:
    1. `whenNotPaused(SEIZE)` — reverts `ContractPaused(SEIZE)`
    2. `onlyRole(SEIZE_ROLE)` — reverts `AccessControlUnauthorizedAccount`
    3. `to == address(0)` — reverts `InvalidReceiver`
    4. `from == address(0)` — reverts `InvalidSender`
    5. `from == to` — reverts `InvalidReceiver` (rejects self-seize)
    6. `from` must NOT be authorized under `SEIZE_HOLDER_POLICY` — else reverts
       `AccountNotSeizable`
    7. `to` must be authorized under `SEIZE_RECEIVER_POLICY` — else reverts
       `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)`
    8. balance check — reverts `InsufficientBalance`
    9. emits, in order: `Transfer(from, to, amount)` → `Memo(caller, memo)` → `Seized(caller, from, to, amount)`
- Admin operation: skips allowance and all three transfer-side policies
  (`TRANSFER_SENDER_POLICY`/`TRANSFER_RECEIVER_POLICY`/`TRANSFER_EXECUTOR_POLICY`)
- Dedicated pause vector: `PausableFeature.SEIZE` pauses `seizeWithMemo` independently. Pausing
  `SEIZE` does not pause `burnBlocked` or transfer operations, and pausing `BURN` or `TRANSFER`
  does not pause seizing.
- Seize is a transfer, not a burn: the balance moves `from` → `to` and `totalSupply` is
  unchanged. This is the key behavioral difference from `burnBlocked`, which sends to
  `address(0)` and reduces supply



### Examples

> Before/after code snippets or call sequences. Expected return values or emitted events.

- Before (old block+burn+mint workaround, still available, deprecated):
    - Configure `from` as blocked under `TRANSFER_SENDER_POLICY`
    - `burnBlocked(from, amount)` — burns `from`'s balance, gated by `BURN_BLOCKED_ROLE`
    - `mint(treasury, amount)` — separately reissues the same amount, gated by `MINT_ROLE`
    - Emits `Transfer(from, 0, amount)` + `BurnedBlocked` + `Transfer(0, treasury, amount)` —
      two independent operations, no single event ties the burn to the reissue
- After (new, single call):
    - Configure `from` as NOT authorized under `SEIZE_HOLDER_POLICY` (i.e. blocked)
    - `seizeWithMemo(from, treasury, amount, memo)` — gated by `SEIZE_ROLE`
    - Emits `Transfer(from, treasury, amount)` → `Memo(caller, memo)` → `Seized(caller, from, treasury, amount)`
---

## Design Decisions & Alternatives Considered

> Describe the approach taken and why. Document alternatives considered and why they were rejected.
> Note any opinionated choices and their rationale.

- **Final shipped shape:** `seizeWithMemo` and `burnBlocked` use fully independent policy slots and
  pause vectors.
  - `seizeWithMemo` uses the new `SEIZE_HOLDER_POLICY` (for `from`) and
    `SEIZE_RECEIVER_POLICY` (for `to`), the new `SEIZE_ROLE`, and the new
    `PausableFeature.SEIZE`.
  - `burnBlocked` retains `TRANSFER_SENDER_POLICY`, `BURN_BLOCKED_ROLE`, and the `BURN` pause
    vector unchanged.

### Function Naming Alternatives

- The shared seize-policy approach was rejected because burning and seizing have different effects:
  `burnBlocked` destroys supply, while `seizeWithMemo` reassigns balances. `burnBlocked` therefore
  remains independent, and no `burnBlockedWithMemo` variant is included.

-  transferFromBlockedWithMemo function name was also brought up
    -  seizeWithMemo is used because it explictly defines the intent 

---

## Migration Steps

> Steps for integrators to adopt the new interface. Call out what is backwards-compatible, any
> deprecation timeline, and breaking changes that require action before activation.

- **Backwards-compatible**: `burnBlocked` continues to work unchanged; no action required if you
  don't need seize behavior yet
- **No breaking changes**: all existing selectors, events, and errors remain dialable
- **To adopt `seizeWithMemo`**:
    1. Grant `SEIZE_ROLE` to the account(s) that should be able to seize — with no `SEIZE_ROLE`
       holders, no one can seize
    2. Configure `SEIZE_HOLDER_POLICY` so the accounts you want seizable are NOT authorized under
       it — with no policy configured (unset = always-allow), no account is seizable
    3. Optionally configure `SEIZE_RECEIVER_POLICY` to restrict where seized funds may land;
       unset defaults to always-allow (e.g. an unallowlisted treasury still works)
- **To reproduce `burnBlocked`'s destroy-supply outcome with seize**: `seizeWithMemo` alone does
  not reduce `totalSupply`. Seize to a treasury/self address, then call `burn(amount)` from that
  address if you want the supply destroyed
- No storage migration: `burnBlocked`'s storage and behavior are untouched by this change
