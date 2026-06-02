# B20

B20 is an ERC-20 superset designed for Base. All B20s are deployed via the singleton `IB20Factory` precompile (see [Factory](Factory.md)).

B20 supports two variants:

- **[Asset](Asset.md)** — the general-purpose variant for assets of all kinds
- **[Stablecoin](Stablecoin.md)** — the fixed-decimals, fiat-backed carveout

This document covers the behavior shared across the variant family.

## ERC-20

Implements the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) standard surface with full selector parity — drop-in for existing tooling.

## Roles model

B20 role-based access control follows from [OZ AccessControl](https://docs.openzeppelin.com/contracts/5.x/access-control) with a fixed set of custom roles and one behavior override on admin renunciation.

Standard role taxonomy:

| Role | Gates |
|---|---|
| `DEFAULT_ADMIN_ROLE` | All admin operations: role grants, policy updates, supply-cap changes |
| `MINT_ROLE` | `mint`, `mintWithMemo` |
| `BURN_ROLE` | Caller-side burns (`burn`, `burnWithMemo`) |
| `BURN_BLOCKED_ROLE` | Sanctions-burns against policy-blocked accounts (`burnBlocked`) |
| `PAUSE_ROLE` | `pause` |
| `UNPAUSE_ROLE` | `unpause` |
| `METADATA_ROLE` | `updateName`, `updateSymbol`, `updateContractURI` |

User-defined roles are supported via `setRoleAdmin` and `grantRole`. They have no built-in effect; B20 only enforces gates against the seven roles above.

Roles are granted, revoked, and renounced through the standard OZ AccessControl methods. The one departure: the last `DEFAULT_ADMIN_ROLE` holder cannot be removed via `renounceRole` or `revokeRole` (both revert with `LastAdminCannotRenounce`); the dedicated `renounceLastAdmin()` is the only path that permanently transitions the token to admin-less. Tokens that intend to launch admin-less from the start pass `initialAdmin == address(0)` at creation, which never grants the role and skips the `renounceLastAdmin` step entirely.

After `renounceLastAdmin()` (or for tokens deployed with `initialAdmin == address(0)`), operations gated by `DEFAULT_ADMIN_ROLE` become permanently uncallable. Roles that were already granted to other addresses (`MINT_ROLE`, `BURN_ROLE`, `PAUSE_ROLE`, `UNPAUSE_ROLE`, `METADATA_ROLE`, etc.) continue to function independently. Admin-resurrection is blocked: `grantRole`, `revokeRole`, and `setRoleAdmin` all revert with `AccessControlUnauthorizedAccount` on an admin-less token, even if the caller holds a custom role that would normally satisfy the meta-role gate. A custom-admin chain such as `setRoleAdmin(MINT_ROLE, BURN_ROLE) → grantRole(BURN_ROLE, X)` cannot restore admin power.

## Policy integration

B20 declares a fixed set of *policy scopes*. Each scope stores a `uint64` policy ID that points into the [PolicyRegistry](../PolicyRegistry/README.md); on every gated operation, B20 calls `isAuthorized` against the relevant scope and reverts (`PolicyForbids`) if the account isn't authorized.

Scope names follow the `{ACTION}_{ACTOR}_POLICY` convention:

| Scope | Gates |
|---|---|
| `TRANSFER_SENDER_POLICY` | The `from` of `transfer` / `transferFrom` |
| `TRANSFER_RECEIVER_POLICY` | The `to` of `transfer` / `transferFrom` |
| `TRANSFER_EXECUTOR_POLICY` | The `msg.sender` of `transferFrom` (not consulted on `transfer`) |
| `MINT_RECEIVER_POLICY` | The `to` of `mint` |

`approve` itself is not policy-gated — only the actual movement of balance via `transfer` / `transferFrom` is checked. A blocked address can hold or receive allowances; the gate fires when balance moves.

Because scopes are per-actor, send-side and receive-side rules can be configured independently. Common patterns include allowlisting receivers while leaving sends open (e.g. KYC-only deposits) and restricting `MINT_RECEIVER_POLICY` to a custodian set while leaving everyday transfers unrestricted.

> ⚠️ **Every scope defaults to `ALWAYS_ALLOW` at token creation** unless overridden in the bootstrap `initCalls`. Token behavior must be intentionally constrained — an unattended deployment of B20 is fully open.

Scopes are read via `policyId(scope)` and written via `updatePolicy(scope, policyId)`. `updatePolicy` is admin-gated and reverts if the scope isn't recognized — typo'd scopes hard-revert rather than silently no-op'ing.

See [PolicyRegistry](../PolicyRegistry/README.md) for registry mechanics (built-in policy IDs, encoding, admin lifecycle).

## Mint

New supply is created via `mint` / `mintWithMemo`, gated by `MINT_ROLE`. The recipient is policy-checked against `MINT_RECEIVER_POLICY`, and the operation reverts with `SupplyCapExceeded` if it would push `totalSupply` past the cap.

## Burn

Two burn paths serve two operational needs:

- **`burn` / `burnWithMemo`** — caller burns from their own balance. Gated by `BURN_ROLE`. Permissioned so asset issuers can maintain equivalent units for wrapped assets without exposing supply to arbitrary holders.
- **`burnBlocked`** — burns from a third party's balance. Gated by `BURN_BLOCKED_ROLE`. The target account MUST be denied by `TRANSFER_SENDER_POLICY` — this is the freeze-and-seize path required by regulated issuers, deliberately impossible against accounts that aren't policy-blocked.

## Supply cap

The supply cap is optional; the sentinel `type(uint256).max` indicates no cap and is the default at creation. `updateSupplyCap(newCap)` is admin-gated and emits `SupplyCapUpdated` — the cap may be raised or lowered freely, but lowering below current `totalSupply` reverts with `InvalidSupplyCap` because already-issued supply is never invalidated.

## Memos

A memo is an optional `bytes32` payload that callers attach to a token operation for off-chain reference — payment IDs, compliance tagging, settlement correlation, etc.

Every memo'd operation emits a `Memo(address indexed caller, bytes32 indexed memo)` event immediately after the operation's primary event, with a `bytes32(0)` memo permitted as a "no memo content" signal. Indexers join the `Memo` log to its parent via `(transactionHash, logIndex − 1)` — the memo always sits immediately after its primary event in log order.

Memo-emitting entrypoints:

- `transferWithMemo`, `transferFromWithMemo` — same semantics as their non-memo counterparts plus the `Memo` event.
- `mintWithMemo`, `burnWithMemo` — same pattern on issuance and self-burn.

## Pause

B20 pauses are granular: the `PausableFeature` enum partitions the gated surface into independently pausable operations, currently `TRANSFER`, `MINT`, and `BURN`. The enum is append-only across protocol versions, so existing positions are stable forever. `isPaused(feature)` is `O(1)`; `pausedFeatures()` returns the full set as an array.

`pause(features)` and `unpause(features)` are gated by *separate* roles (`PAUSE_ROLE` and `UNPAUSE_ROLE`) by design — an incident-response operator can pause without holding the authority to re-enable.

## ERC-2612 Permit / EIP-712

B20 implements [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) (signed approvals) using an [EIP-712](https://eips.ethereum.org/EIPS/eip-712) domain shaped as `(name, version, chainId, verifyingContract)`, with `version` fixed at `"1"` and `salt` unused. Because `name` is re-hashed into the domain on every signed call, `updateName` automatically rotates the domain separator; each successful `updateName` emits one `EIP712DomainChanged` event ([ERC-5267](https://eips.ethereum.org/EIPS/eip-5267)).

`DOMAIN_SEPARATOR()` and `eip712Domain()` are exposed for callers that want to read the domain dynamically rather than reconstruct it. `nonces(owner)` is the per-account replay counter incremented on every `permit`.

ERC-1271 contract signatures are deliberately NOT accepted — permit recovers via ECDSA from 65-byte signatures only. Smart-contract accounts should use call-batching or gasless flows. [Permit2](https://github.com/Uniswap/permit2) is usable as a periphery alternative.

## Contract URI (ERC-7572)

`contractURI()` returns a string pointing to off-chain metadata about the token (typically a JSON document) per [ERC-7572](https://eips.ethereum.org/EIPS/eip-7572). `updateContractURI(newUri)` is gated by `METADATA_ROLE`.

## Metadata updates

`METADATA_ROLE` gates two metadata setters:

- `updateName(newName)` updates the token name AND rotates the EIP-712 domain separator (see [ERC-2612 Permit / EIP-712](#erc-2612-permit--eip-712)). Emits `NameUpdated` and `EIP712DomainChanged`.
- `updateSymbol(newSymbol)` updates the symbol with no other side effects. Emits `SymbolUpdated`.

## Variant overview

| Variant | Decimals | What it adds |
|---|---|---|
| [Asset](Asset.md) | 6-18 (configurable per token) | multiplier, announcements, extra metadata, batched issuance |
| [Stablecoin](Stablecoin.md) | 6 (fixed) | currency ISO code |
