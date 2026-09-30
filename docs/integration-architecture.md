# B20 Integration Architecture

*What a caller can observe and rely on. This document describes B20's externally observable architecture and the properties third-party integrators can build against. It does not describe the internal implementation of B20 in `base/base`.*

*For the product tour, see [Overview](overview.md). For roles, policies, and token types, see [Concepts](concepts/). For the event list, see [Events](reference/events.md).*

## 1. Mental Model

A B20 is an account you call like a contract. You send ABI-encoded calldata to an address. The call returns data, reverts with a custom error, or emits events. Balances, transfers, and approvals follow ERC-20. Roles, pause, mint, burn, seize, and policies are part of the same interface.

The protocol provides that execution. You do not deploy per-token logic, and the account does not carry a program you maintain. Every token of a variant exposes the same interface, so a wallet, an issuer, or an app integrates once.

Two properties follow for a caller:

- A successful call commits state at the target address. A revert restores that call's writes, the same way a contract revert does.
- A later view returns the state those writes committed. `balanceOf`, `hasRole`, `isPaused`, and `isAuthorized` read that state directly.

Asset and Stablecoin share this shape. They differ in the extra interface at the same address. See [Token Types](concepts/token-types.md).

## 2. System Surface

Four components matter to an integrator. Three are singletons at fixed addresses. Tokens are many addresses, each created by the Factory.

| Component | Address | What you call it for |
| --- | --- | --- |
| Factory | `0xB20f000000000000000000000000000000000000` | `createB20`, `getB20Address`, `isB20`, `isB20Initialized` |
| Policy Registry | `0x8453000000000000000000000000000000000002` | Shared allowlists, blocklists, and composite policies |
| Activation Registry | `0x8453000000000000000000000000000000000001` | Whether a Factory or token feature is on |
| B20 token | Derived by `createB20` | Balances, transfers, roles, pause, mint, burn, seize, and the policy IDs bound to that token |

The Factory creates a token and then stops. After `createB20` returns, the Factory has no further access to that token.

The Policy Registry holds the lists. A token stores a policy ID, not the members. Many tokens can store the same ID. An update to that policy changes `isAuthorized` for every token that stores it. Those tokens do not need another `updatePolicy`.

The Activation Registry is a Base-operated switch. Issuers and apps read it. When a feature is inactive, writes that require it revert with `FeatureNotActivated`. Reads stay available. Turning a variant off stops new `createB20` calls for that variant. Tokens that already exist keep running.

Constants for these addresses live in [`StdPrecompiles`](../src/StdPrecompiles.sol).

## 3. Identity and Code

### 3.1 What appears at a token address

`getB20Address(variant, sender, salt)` returns the address `createB20` will use. It never reverts. If that account is already occupied, `createB20` reverts `TokenAlreadyExists`.

The address is self-describing:

- Byte `[0]` is `0xB2`.
- Bytes `[1:9]` are zero.
- Byte `[10]` is the variant. Asset is `0x00`. Stablecoin is `0x01`.
- The remaining bytes are derived from `keccak256(sender, salt)`.

Byte `[10]` is the type, and it does not change after `createB20` returns. An Asset address exposes [`IB20`](../src/interfaces/IB20.sol) and [`IB20Asset`](../src/interfaces/IB20Asset.sol). A Stablecoin address exposes `IB20` and [`IB20Stablecoin`](../src/interfaces/IB20Stablecoin.sol). A selector that belongs to the other variant does not run on that address.

`isB20(address)` reports the `0xB2` prefix only. It can return true for an address the Factory has not created, and it never reverts. `isB20Initialized(address)` is the liveness check. It flips once, when the creating `createB20` returns, and it never reverts. During `initCalls` in that same call, it is still false.

Before creation, the predicted address has no code. A call to it returns no output. It is not a token yet.

### 3.2 What `0xef` means

On creation, the Factory sets the account code to a single byte, `0xef`. That is the entire code. It is a marker, not a program. B20 tokens are not EVM contracts, so there is no bytecode to verify or upgrade at that address.

`0xef` is the [EIP-3541](https://eips.ethereum.org/EIPS/eip-3541) reserved prefix. Ordinary `CREATE` and `CREATE2` cannot deploy code that starts with it. An address with the `0xB2` prefix and this code came from the Factory.

### 3.3 How tooling should read that code

Use the code as an identity check. Call the token through its ABI.

- `eth_getCode` on a created token returns `0xef`. The size is 1. Both variants use that same byte. Read the variant from address byte `[10]`, or from `B20Created.variant`.
- Treat `isB20` as a prefix filter. Treat `isB20Initialized`, or the pair of prefix plus code `0xef`, as "this token exists."
- Decode calls and logs with `IB20`, plus `IB20Asset` or `IB20Stablecoin`. The code byte is not the interface.
- Index creation from `B20Created`. The Factory emits it once, after identity is sealed and before `initCalls`.

## 4. State and Events

Views return current state. Events are the log of changes. Some events are a complete record of the change. Some are not. When they are not, query the view.

Token state sits in the token account. Shared list state sits in the Policy Registry account. A balance write on one token is not visible on another. A membership write on a policy is visible to every token that stores that policy ID.

The exhaustive list is in [Events](reference/events.md). The rules below are the ones that change how you index.

### 4.1 Read the view

| What you need | Call | Why the log is not enough on its own |
| --- | --- | --- |
| Balance, allowance, total supply | `balanceOf`, `allowance`, `totalSupply` | A full `Transfer` and `Approval` log from creation can rebuild these. A gap cannot. |
| Role membership | `hasRole` | `RoleGranted` and `RoleRevoked` fire only when membership changes. Idempotent `grantRole` and `revokeRole` emit nothing. A gap, including a missed creation grant, leaves the set wrong. |
| Paused features | `isPaused`, `pausedFeatures` | `Paused` and `Unpaused` carry the array you passed, not the resulting set. Duplicates and features already in that state are still in the array. |
| Policy bound to a scope | `policyId` | `PolicyUpdated` carries the old and new IDs when you have the log. After a gap, read the view. An unset scope reads as `0`. |
| Policy decision | `isAuthorized` | Membership events are not enough once a composite or the invert bit is involved. `isAuthorized` never reverts. |
| Contract URI | `contractURI` | `ContractURIUpdated` has no arguments. |
| UI multiplier | `uiMultiplier` | A scheduled update emits `UIMultiplierUpdated` with `effectiveAtTimestamp`. The value in effect is the view. `newUIMultiplier` and `effectiveAt` expose the pending schedule. |
| Feature activation | `isActivated` | An inactive write reverts `FeatureNotActivated`. The read still works. |

### 4.2 Events you can take as the change

When your log is complete from the relevant start (token creation, or policy creation), these payloads are the change itself:

- `Transfer` and `Approval` follow ERC-20. Mint uses `from = address(0)`. Burn uses `to = address(0)`.
- `Memo` follows a memo'd transfer, mint, or burn. `Seized` follows `seizeWithMemo`, in addition to `Transfer`.
- `RoleGranted` and `RoleRevoked` record a real membership change. `RoleAdminChanged` carries the previous and new admin role. `LastAdminRenounced` accompanies the final `RoleRevoked` for `DEFAULT_ADMIN_ROLE`.
- `PolicyUpdated` carries `oldPolicyId` and `newPolicyId`. A binding at creation can emit it with `oldPolicyId == 0`.
- `SupplyCapUpdated`, `NameUpdated`, and `SymbolUpdated` carry the new value. `updateName` also emits `EIP712DomainChanged`. `updateSymbol` does not.
- `AllowlistUpdated` and `BlocklistUpdated` carry the batch and the new membership bit. `CompositePolicyUpdated` carries the full child set after the write.
- `PolicyAdminStaged` carries the pending admin. `PolicyAdminUpdated` carries the previous and new admin.
- `B20Created` carries token, variant, name, symbol, and decimals. `variantEventParams` is empty for Asset. For Stablecoin it is the ABI-encoded currency.
- `FeatureActivated` and `FeatureDeactivated` carry the feature id.

## 5. State Transitions

Each transition is defined by the views a later call sees and the events that fire. Role and pause details are in [Roles and Pause](concepts/roles-and-pause.md). Policy details are in [Policies](concepts/policies.md).

### 5.1 Create a token

`createB20(variant, salt, params, initCalls)` is the only creation path.

On success:

1. The account at the predicted address has code `0xef`.
2. Name, symbol, decimals, and the variant-specific identity are sealed. The variant does not change later.
3. The Factory emits `B20Created`.
4. If `initialAdmin` is not `address(0)`, that account holds `DEFAULT_ADMIN_ROLE` and the token emits `RoleGranted`. `address(0)` skips the grant, and the token has no admin.
5. `initCalls` run on the new token in the same transaction. They can grant roles, bind policies, or mint. A reverting init call reverts the creation.
6. `createB20` returns the token address. `isB20Initialized` becomes true. The Factory's access ends with that return.

Pause starts clear. To start paused, put `pause` last in `initCalls`. Pause is enforced during init, so an earlier init call still sees the features as live. `MINT_RECEIVER_POLICY` is also enforced during init. A mint in `initCalls` to an account that policy rejects reverts the creation.

### 5.2 Announce, re-announce, and accept a policy admin

A policy has one admin. Handing it off takes two calls. The first call announces a successor and does not transfer control.

`stageUpdateAdmin(policyId, newAdmin)` is the announcement. The caller is the current admin. After it returns:

- `policyAdmin` is unchanged. That admin can still update membership.
- `pendingPolicyAdmin` is `newAdmin`.
- The registry emits `PolicyAdminStaged`.

A second `stageUpdateAdmin` is a re-announcement. It replaces the pending admin. `newAdmin = address(0)` clears the nomination and leaves the current admin in place.

`finalizeUpdateAdmin(policyId)` is the accept. The caller is the staged address. After it returns:

- `policyAdmin` is the caller.
- `pendingPolicyAdmin` is `address(0)`.
- Membership updates from the previous admin revert `Unauthorized`.
- The registry emits `PolicyAdminUpdated`.

If nothing is staged, `finalizeUpdateAdmin` reverts `NoPendingAdmin`. Any other caller reverts `Unauthorized`.

`renounceAdmin` is a different ending. The current admin becomes `address(0)`. Membership and child sets no longer change. `isAuthorized` still answers. No later call assigns a new admin.

Token administration is separate. It is `grantRole` and `revokeRole` on the token, not this two-step. See [Roles and Pause](concepts/roles-and-pause.md).

### 5.3 Pause

`pause(features)` requires `PAUSE_ROLE`. `unpause(features)` requires `UNPAUSE_ROLE`. The two roles are independent, so the account that pauses does not have to be the account that resumes.

The features are `TRANSFER`, `MINT`, `BURN`, and `SEIZE`. Pausing one leaves the others live. `approve` is not pause-gated. A holder `transfer` is not role-gated. It still stops when `TRANSFER` is paused, and it still passes through policy.

After a successful `pause`, `isPaused` is true for each listed feature that was not already paused. The token emits `Paused(updater, features)` with the array you passed. Read `pausedFeatures()` for the set. A later call that uses a paused feature reverts `ContractPaused` and names that one feature.

An empty array reverts `EmptyFeatureSet`. A feature that is already in the requested state does not revert. It is a no-op, and it is still present in the event array.

### 5.4 Policy updates

Two writes are distinct.

`updateAllowlist`, `updateBlocklist`, and `updateComposite` change the Policy Registry. Only the policy admin can call them. The next `isAuthorized` uses the new membership or the new child set. Every token that already stores that policy ID sees the new result, with no transaction on the token. The registry emits `AllowlistUpdated`, `BlocklistUpdated`, or `CompositePolicyUpdated`.

`updatePolicy(scope, newPolicyId)` changes the token. It requires `DEFAULT_ADMIN_ROLE`. It selects which policy ID a scope checks. It does not edit the list. The token emits `PolicyUpdated`. Until you set a scope, `policyId` returns `0` (`ALWAYS_ALLOW`).

Binding a policy ID does not make the token's admin the policy's admin. Anyone can create a policy. Attaching an existing ID reuses that list and leaves its admin unchanged.

## 6. Protocol Evolution

Base changes B20 in protocol upgrades. On Base those upgrades are hardforks. For an integrator, a hardfork can introduce a new precompile, or it can change the logic that answers at an address you already call.

What stays stable:

- Singleton addresses do not move. The Factory, the Policy Registry, and the Activation Registry stay at the addresses in [§2](#2-system-surface).
- A token address does not move, and byte `[10]` does not change.
- A call in a past block keeps the result it had in that block. A node that replays history from genesis reaches the same state as a node that was live for those blocks. An upgrade does not rewrite blocks that already executed.
- After the upgrade, new calls use the upgraded behavior at the same address. You do not point your integration at a new token address to pick up the upgrade.
- A call the active protocol cannot serve reverts. There is no fallback to some other behavior.
- Deactivation does not delete an address. Writes that require the inactive feature revert `FeatureNotActivated`. Reads remain. Deactivating a variant blocks new `createB20` calls for that variant. Existing tokens keep running.

Integrate against the interface of the release you are on. A later hardfork can add selectors at these same addresses. Those selectors are absent until that hardfork.

## 7. Integration Guarantees

### 7.1 Contractual

These properties are the external behavior of the interfaces in this repository. You can build on them.

- Call B20 with the contract ABI at the singleton addresses in [§2](#2-system-surface), and at token addresses from `getB20Address` and `createB20`.
- `createB20` is the only creation path. The address is determined by `(variant, sender, salt)`.
- A completed token has code `0xef` and the address shape in [§3.1](#31-what-appears-at-a-token-address). `isB20Initialized` means creation has returned. `isB20` means the prefix matches.
- Byte `[10]` is fixed after creation. It selects `IB20Asset` or `IB20Stablecoin` in addition to `IB20`.
- The views in [§4.1](#41-read-the-view) return current state. The events in [§4.2](#42-events-you-can-take-as-the-change) report the changes they name, with the pause and idempotent-role caveats in [§4](#4-state-and-events).
- A revert restores the state writes of that call.
- After `createB20` returns, the Factory cannot act on that token.
- A Policy Registry update is visible to every token that stores that policy ID.
- Across a hardfork, the addresses in [§2](#2-system-surface) stay put, and historical execution stays put, as in [§6](#6-protocol-evolution).
- An inactive feature rejects the writes that require it with `FeatureNotActivated`. It does not remove existing tokens, and it does not disable reads.

### 7.2 Non-contractual

These are outside the integration contract.

- How the client decides to run the call, and any other detail of the implementation in `base/base`.
- Storage slot numbers and packing. Use the views. Account storage is readable with `eth_getStorageAt`, and the slot layout is not an interface.
- Exact gas. A call can run out of gas and revert. The amounts can change across upgrades.
- Treating `Paused.features` or `Unpaused.features` as the full paused set.
- Treating `isB20 == true` as proof that the token exists.
- Calling `activate` or `deactivate`. Base operates the Activation Registry. Integrations read `isActivated`.
- Selectors, events, or variants that a future hardfork might add. They are not available early, and this document does not promise a specific future feature.
- Executing or extending the `0xef` byte. It is the marker the Factory plants. EIP-3541 rejects a normal deployment whose code starts with that byte.
