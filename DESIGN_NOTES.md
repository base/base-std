# Design Notes

The interfaces in `src/interfaces/` enshrine the minimum protocol-level
surface needed for a Base-native ERC-20: balance state, raw transfer
mechanics, a policy hook for compliance, a pause flag, and a binding
to an EVM wrapper contract that owns all governance and product
behavior. Everything else is wrapper-level.

## The architectural unit: precompile + wrapper

A B-20 token is a **pair**:

- A **precompile** (`IB20`) that owns the balance state, the raw
  transfer mechanics, the policy hook, and the pause flag.
- An **EVM wrapper contract** that owns all authorization, all role
  logic, and all product-specific behavior.

The pair is created atomically by the factory, and the binding is
permanent: the precompile knows its wrapper address (`wrapper()`),
and only that wrapper can call the precompile's privileged operations.

The model is the OZ `_internal` / `public` split, but enforced at the
protocol level rather than by Solidity inheritance:

- **Precompile-public** functions (callable by anyone): the standard
  ERC-20 surface (`transfer`, `transferFrom`, `approve`, plus
  metadata and balance reads) and read-only state accessors
  (`wrapper`, `paused`, `transferPolicyId`).
- **Precompile-internal** functions (callable only by the wrapper):
  `mint`, `burn`, `wrapperTransfer`, `setPaused`,
  `setTransferPolicyId`. Revert with `OnlyWrapper` for any other
  caller.

The wrapper is a normal EVM contract. Issuers design it to fit their
product:

- A **stablecoin wrapper** adds RBAC, per-minter rate limits, EIP-2612
  permit, ERC-3009 transfer-with-authorization, paying-agent
  integrations.
- A **security token wrapper** adds corporate actions, share-ratio
  accounting, brokerage redeem flows, announcement-coupled metadata
  changes.
- A **minimal wrapper** adds nothing and exposes a thin `mint` /
  `burn` API gated by `Ownable`.

### Wrapper upgradability

The wrapper address is immutable on the precompile, set at creation.
If the wrapper bytecode needs to change post-creation (bug fix, new
feature), the wrapper itself uses a proxy pattern (transparent proxy,
beacon proxy, etc.). The proxy is the immutable wrapper from the
precompile's perspective; the implementation behind the proxy is
upgradable per the proxy's own governance rules.

This pushes all upgrade complexity into EVM, where it's well-
understood. The precompile carries zero state related to upgrade
authority.

## Design principles

### Minimum enshrinement

Anything in a precompile is permanent until a hardfork. The bar for
inclusion is whether the feature must live at the protocol level
because either (a) it cannot be expressed in EVM at all, or (b)
protocol-level behavior depends on it (most importantly, gas
payment).

Specifically included:

1. **ERC-20 surface** (balances, transfers, approvals, metadata).
   Required for ecosystem compatibility and so the chain can read
   token state during gas payment.
2. **Mint and burn**, callable only by the bound wrapper. Required
   because the precompile owns supply state.
3. **Policy hook** (`transferPolicyId`). Required so compliance
   enforcement applies at the protocol level, including during gas
   payment.
4. **Pause flag**. Required so the same protocol-level halt applies
   to gas payment as to user transfers.
5. **`wrapperTransfer`**. Required to support wrapper-mediated
   authorization flows (permit, ERC-3009) without forcing every
   user to maintain a precompile-level allowance.
6. **Wrapper binding**. Required to authorize `mint` / `burn` /
   `setPaused` / `setTransferPolicyId` / `wrapperTransfer`. One
   immutable address answers all "who can call this?" questions for
   privileged operations.

Specifically excluded (lives in wrappers):

- Role-based access control of any flavor (admin, issuer, pauser,
  minter, RBAC, OZ AccessControl).
- Two-step admin or issuer rotation.
- Configurable transfer delays.
- EIP-2612 permit, ERC-3009, transfer memos.
- Per-minter rate limiting.
- Supply caps.
- Contract URI, currency identifier, asset type, share ratio,
  corporate actions, dividend distribution, brokerage redeem flows.

### Policies are the single source of truth for compliance

Every balance-mutating operation that moves value passes through the
policy registry referenced by `transferPolicyId`. The hook fires on:

- **Transfers** (`transfer`, `transferFrom`, `wrapperTransfer`):
  `isAuthorizedSender(transferPolicyId, from)` and
  `isAuthorizedRecipient(transferPolicyId, to)`.
- **Mints**: `isAuthorizedMintRecipient(transferPolicyId, to)`. The
  caller authority check is the wrapper check, not a policy check.
- **Burns**: no policy check. Burns reduce supply and are
  deliberately available for compliance enforcement (sanctions
  seizure). Authority is the wrapper check.

A single shared policy can serve every B-20 token on the chain
(sanctions list, KYC allowlist, jurisdiction restrictions, etc.). To
update sanctions across all B-20 tokens, you update one policy in one
place.

### Gas payment is a transfer

When a B-20 token is configured as a gas asset, fee debits flow
through the same `transferPolicyId` check as user-initiated
transfers. The chain does NOT special-case fee payment to bypass the
policy. A sanctioned account that cannot transfer also cannot pay
gas in the token. A paused token cannot pay gas at all. This is the
intended behavior and is the primary justification for enshrining
both the policy hook and the pause flag alongside the balance state.

The corollary: tokens that want to be gas assets must register a
policy that doesn't accidentally lock out legitimate users from fee
payment. Wrapper / issuer responsibility, not a protocol concern.

### `wrapperTransfer` rationale

`transferFrom` requires the caller to have an allowance from `from`.
For wrapper-mediated flows like permit and ERC-3009, the user signs
authorization off-chain and the wrapper executes the transfer; there
is no on-chain allowance to consume.

`wrapperTransfer(from, to, amount)` is the precompile's escape hatch
for this case. Wrapper-only. Skips the allowance check. Subject to
the same policy and pause checks as `transfer`. The wrapper is
trusted (because the precompile only allows it as the caller) to
have verified user authorization off-chain.

Without this, the wrapper would have to maintain its own per-account
shadow allowance state, or require every user to first
`approve(wrapper, type(uint256).max)`. Both are awkward and gas-
expensive compared to a single privileged call.

### No third-party dependencies

Reference implementations are written from scratch. We can read
OpenZeppelin, Tempo, CCS, Tangor, and other prior art for
inspiration; we don't import. The reasoning: it's too easy to absorb
someone else's interface decisions wholesale instead of reaching our
own opinions. Revisit when the interfaces stabilize.

## What lives in EVM wrappers

Almost everything that isn't on the `IB20` surface. Concrete
examples, each previously considered for enshrinement and explicitly
moved out:

- **Authorization for privileged operations**: who can call `mint`,
  `burn`, `setPaused`, `setTransferPolicyId`. The wrapper exposes its
  own public `mint(...)` / `pause()` / etc. with whatever auth model
  it wants (single owner, multi-sig, RBAC, timelock, governance
  contract) and delegates to the precompile.
- **Two-step admin / issuer rotation with delays**: standard OZ
  `AccessControlDefaultAdminRules` pattern in the wrapper. The
  precompile knows nothing about it.
- **EIP-2612 permit / ERC-3009 transfer with authorization**: gasless
  flows. Wrapper verifies the signature and calls
  `precompile.wrapperTransfer(from, to, amount)`.
- **Memos / transfer metadata**: wrapper exposes
  `transferWithMemo(...)` that emits a memo event before delegating
  to the precompile.
- **Per-minter rate limiting**: wrapper tracks per-caller quotas in
  its own storage and enforces them on its public `mint(...)`.
- **Corporate actions, share ratio, brokerage redeem**: wrapper
  exposes typed action functions and composes the precompile
  primitives.
- **Currency identifier, contract URI, asset type, reserve
  attestation URI, etc.**: wrapper exposes the views.

Pattern: the precompile owns balance and compliance primitives;
wrappers compose those primitives into product-specific behavior.

## Policy registry

`IPolicyRegistry` is a singleton precompile at a fixed address. Three
policy types in v1: WHITELIST, BLACKLIST, and COMPOUND. COMPOUND
policies reference three constituent simple policies (sender,
recipient, mint-recipient slots) for asymmetric rules.

Policy IDs `0` (always-reject) and `1` (always-allow) are built-in;
custom IDs start at `2` and are assigned monotonically. Anyone may
create policies; the creator picks the policy admin (typically
themselves or a multi-sig).

Adapted from Tempo TIP-403 + TIP-1015. Three deliberate omissions:

- **No virtual-address rejection (TIP-1022)**: incompatible with our
  hard requirement that B-20 tokens coexist with the existing Base
  ERC-20 ecosystem and addresses.
- **No receive policies (TIP-1028)**: no concept of escrow on Base.
- **No callback / richer guard policies**: extending the enum later
  is backward-compatible, and reserving the value now buys nothing
  because the actual implementation requires a hardfork either way.
  Defer.

For rules outside the WHITELIST / BLACKLIST / COMPOUND vocabulary
(per-tx amount limits, time-windowed access, oracle-driven gating,
attestation-based eligibility), wrappers compose: do the rich check
first, then call `precompile.transferFrom` or `wrapperTransfer`.

## Pause semantics

Pause is a boolean read by the precompile on every balance-mutating
path. While paused:

- `transfer`, `transferFrom`, `mint`, `burn`, `wrapperTransfer`
  revert with `ContractPaused`.
- `approve`, `setPaused`, `setTransferPolicyId` remain available so
  the wrapper can prepare state changes while the token is halted.

The precompile knows nothing about pause authorization; `setPaused`
is wrapper-only. The wrapper exposes whatever pause API it wants
(simple admin pause, multi-sig pause, time-locked pause, separate
pause and unpause roles, etc.).

`setPaused` is idempotent: calling with the current value is a no-op
and emits no event.

## What's not in this draft

- **Token factory.** The factory's job is to atomically deploy the
  precompile + wrapper pair, bind them, and register the binding.
  Open whether this is itself a precompile or some other chain-
  config flow.
- **Reference wrappers.** Likely follow once the precompile interface
  stabilizes:
  - `MinimalWrapper.sol`: single-owner, exposes raw `mint` / `burn` /
    `pause` / `setTransferPolicyId` with `Ownable`-style auth.
    Suitable for memecoins, fixed-supply tokens, simple cases.
  - `StablecoinWrapper.sol`: RBAC + per-minter rate limits + EIP-2612
    permit + ERC-3009. Suitable for CCS-style stablecoins.
  - `SecurityTokenWrapper.sol`: corporate actions + share ratio +
    brokerage redeem + announcement coupling. Suitable for tokenized
    equities.
- **Reference Solidity implementation of `IB20`**.

## Open questions

1. **Wrapper rotation**: should the precompile expose any path for
   the bound wrapper to designate a successor (one-step or two-step
   wrapper swap)? Default position: no, wrappers are immutable; use
   a proxy pattern internally if upgrades are needed. Argument for
   adding: simpler for issuers who don't want to deal with proxies.
   Argument against: re-introduces governance state on the
   precompile.
2. **Initial supply at creation**: should the factory accept an
   `initialSupply` parameter that bootstraps the token before any
   wrapper-mediated mint? Bypasses the policy check (no policy may
   be configured yet). Useful for fixed-supply tokens.
3. **Burn-during-pause**: currently burn is wrapper-only and blocked
   by pause. Should burn bypass pause so wrappers can execute
   compliance burns even during a halt? Or stays as-is?
4. **`setTransferPolicyId` validation**: the precompile reverts with
   `InvalidPolicyId` if the policy doesn't exist in the registry.
   This requires a registry call on every set. Cheap, but worth
   confirming we want the validation rather than trusting the
   wrapper to set valid IDs.
