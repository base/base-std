# Transfer Executor Policy Enforcement

- **Feature Name**: transfer_executor_enforcement
- **Start Date**: 2026-09-10
- **Authors**: Rayyan Alam
- **Title**: (Breaking) Transfer Executor Policy Enforcement

## Summary

This change makes `TRANSFER_EXECUTOR_POLICY` apply to every transfer path. The executor gate now checks `msg.sender` on `transfer`, `transferFrom`, `transferWithMemo`, and `transferFromWithMemo`, including when `msg.sender == from`. Previously the check ran only on the delegated `transferFrom` paths, and only when `msg.sender != from`.

This is a breaking change for a token that already set a restrictive `TRANSFER_EXECUTOR_POLICY`. Holders who moved their own tokens with `transfer` or self-`transferFrom` must now be authorized as initiators. A token that never set the policy keeps the unset always-allow default and is unaffected.

The change is purely behavioral. It adds no new selectors, events, errors, or storage.

## Motivation

An issuer of a restricted security token may need every transfer to go through a registered transfer agent. In that model, only the transfer agent's contract may initiate a move. A holder cannot call `transfer` themselves, even to an already-eligible counterparty. The holder approves the transfer agent, and the transfer agent calls `transferFrom`.

`TRANSFER_EXECUTOR_POLICY` is the initiator allowlist for that pattern. The previous scope could not enforce it consistently with `TRANSFER_SENDER_POLICY` and `TRANSFER_RECEIVER_POLICY`, which already run on every transfer path.

The previous scope left two initiator-side gaps:

1. `transfer` never consulted the executor policy. The initiator of `transfer` is `msg.sender`, which is also `from`, but the check lived only inside `transferFrom`. A holder could always move their own tokens through `transfer`, regardless of the executor allowlist.
2. `transferFrom` skipped the check when `msg.sender == from`. A holder could route a self-`transferFrom(from, to, amount)` call to reach the same unchecked path, even if they were not on the executor allowlist.

Both gaps let a non-allowlisted holder move tokens by choosing a different entrypoint, so the executor scope could not express "only these initiators may move tokens" for any holder. Centralizing the check on `msg.sender` and removing the `msg.sender == from` carve-out closes both gaps and brings `TRANSFER_EXECUTOR_POLICY` to parity with the sender and receiver scopes.

## Background

### Policy Registry and transfer-side scopes

The Policy Registry is a singleton precompile that B20 tokens call for pre-operation compliance checks on an address. A B20 token stores a `uint64` policy ID per scope and calls `isAuthorized(policyId, account)` before a gated operation. `isAuthorized` never reverts; a malformed or unknown ID returns `false` (deny). See [Policies](../docs/concepts/policies.md) for the full model.

B20 has three transfer-side scopes, all checked inside the shared `_transfer` function that backs `transfer`, `transferFrom`, and their memo variants:

| Scope | Account checked |
| --- | --- |
| `TRANSFER_SENDER_POLICY` | `from` |
| `TRANSFER_RECEIVER_POLICY` | `to` |
| `TRANSFER_EXECUTOR_POLICY` | `msg.sender` |

All three scopes are bypassed during the factory bootstrap window (`_isPrivileged()`), so a token's `initCalls` can move newly minted supply without pre-authorizing itself under any of the three policies. See [`IB20Factory.createB20`](../src/interfaces/IB20Factory.sol).

`transferFrom` and `transferFromWithMemo` additionally consume the caller's allowance from `from` before reaching `_transfer`. Allowance accounting is unconditional, including during the bootstrap window, and is unaffected by this change.

## Specs

### Interface Changes

This change adds no new functions, events, errors, or selectors. The change is behavioural: it alters how the existing transfer functions enforce `TRANSFER_EXECUTOR_POLICY`.

### Behavioural Changes

The executor check moves from the `transferFrom` and `transferFromWithMemo` bodies into `_transfer`, where it runs first, before the existing sender and receiver checks, and under the same `_isPrivileged()` bootstrap bypass. The `msg.sender == from` carve-out that previously skipped the check is removed. `transfer` and `transferWithMemo` route through the same `_transfer` function, so they gain the check with no entrypoint-specific code.

Pause, zero-actor, and allowance checks stay in the entrypoints. This change only moves the three transfer-side policy checks into the helper.

The previous order, by entrypoint:

```mermaid
flowchart TD
    subgraph beforeTransfer ["Before: transfer / transferWithMemo"]
        BT1[pause] --> BT2[zero-receiver]
        BT2 --> BT3[zero-sender]
        BT3 --> BT4[sender policy]
        BT4 --> BT5[receiver policy]
        BT5 --> BT6[balance]
    end

    subgraph beforeTransferFrom ["Before: transferFrom / transferFromWithMemo"]
        BF1[pause] --> BF2[zero-receiver]
        BF2 --> BF3[zero-sender]
        BF3 --> BF4[allowance]
        BF4 --> BF5{"msg.sender != from?"}
        BF5 -->|yes| BF6[executor policy]
        BF5 -->|no: skip| BF7[sender policy]
        BF6 --> BF7
        BF7 --> BF8[receiver policy]
        BF8 --> BF9[balance]
    end
```

This reorders the checks a caller can hit. Both paths now enter `_transfer` for the three transfer-side policies. The canonical order is now:

- `transfer` / `transferWithMemo`: pause → zero-receiver → zero-sender → **executor policy** → sender policy → receiver policy → balance.
- `transferFrom` / `transferFromWithMemo`: pause → zero-receiver → zero-sender → allowance → **executor policy** → sender policy → receiver policy → balance.

```mermaid
flowchart TD
    AT["transfer / transferWithMemo"] --> AT1[pause]
    AT1 --> AT2[zero-receiver]
    AT2 --> AT3[zero-sender]
    AT3 --> XE

    AF["transferFrom / transferFromWithMemo"] --> AF1[pause]
    AF1 --> AF2[zero-receiver]
    AF2 --> AF3[zero-sender]
    AF3 --> AF4[allowance]
    AF4 --> XE

    subgraph xfer ["_transfer"]
        XE[executor policy] --> XS[sender policy]
        XS --> XR[receiver policy]
        XR --> XB[balance]
    end
```

When more than one check would fail, the caller sees the first revert in that order.

### Gas

This change adds no new storage slots. `_transfer` reads all three transfer-side policy IDs from the existing packed slot in one `SLOAD`.

On `transferFrom` and `transferFromWithMemo`, the previous implementation read the executor lane in the entrypoint body, then read the same packed slot again in `_transfer` (warm). The helper now performs the only `SLOAD`.

On `transfer` and `transferWithMemo`, the previous implementation did not consult the executor policy. Those paths now make one extra `isAuthorized` call against `msg.sender`. Sender and receiver checks are unchanged.

An unset executor slot remains `ALWAYS_ALLOW_ID` (`0`). The Policy Registry still answers that call. The extra work is one `isAuthorized` lookup, not a storage write.

### Examples

A holder moving their own tokens is now gated by the executor policy, even through direct `transfer`:

```solidity
token.updatePolicy(TRANSFER_EXECUTOR_POLICY, ALWAYS_BLOCK_ID);

vm.prank(alice);
token.transfer(bob, amount); // reverts PolicyForbids(TRANSFER_EXECUTOR_POLICY, ALWAYS_BLOCK_ID)
```

An executor allowlist restricts initiation to approved accounts, such as a transfer agent. A holder who is a member can move their own tokens. A holder who is not a member cannot:

```solidity
uint64 executorAllowlist = policyRegistry.createPolicyWithAccounts(admin, ALLOWLIST, [transferAgent]);
token.updatePolicy(TRANSFER_EXECUTOR_POLICY, executorAllowlist);

vm.prank(transferAgent);
token.transferFrom(alice, bob, amount); // succeeds: transferAgent is allowlisted

vm.prank(alice);
token.transfer(bob, amount); // reverts PolicyForbids(TRANSFER_EXECUTOR_POLICY, ...): alice is not allowlisted
```

The factory bootstrap bypass still applies. A token's `initCalls` can mint and transfer even when the freshly configured executor policy would otherwise block the factory:

```solidity
initCalls = [
    abi.encodeCall(IB20.mint, (address(factory), amount)),
    abi.encodeCall(IB20.updatePolicy, (TRANSFER_EXECUTOR_POLICY, ALWAYS_BLOCK_ID)),
    abi.encodeCall(IB20.transfer, (to, amount))
];
factory.createB20(..., initCalls); // succeeds: bootstrap window bypasses the executor check
```

## Design Decisions & Alternatives Considered

### Chosen: centralize the check in `_transfer`, on `msg.sender`

The executor check moves into the shared `_transfer` helper. `transfer`, `transferFrom`, `transferWithMemo`, and `transferFromWithMemo` already call `_transfer`, so they all run the same executor check on `msg.sender`. `transferWithMemo` and `transferFromWithMemo` therefore get the same coverage as the non-memo paths, with no entrypoint-specific code. The check has no `msg.sender == from` carve-out and still honors the existing `_isPrivileged()` bypass.

This approach was chosen because it is the smallest change that closes both gaps described in Motivation, adds no new interface surface, and brings `TRANSFER_EXECUTOR_POLICY` in line with how `TRANSFER_SENDER_POLICY` and `TRANSFER_RECEIVER_POLICY` are already enforced: once, in `_transfer`, on every path.

Pause, zero-actor, and allowance stay in the entrypoints. Pause is a modifier shared with mint, burn, and seize. Allowance is unique to `transferFrom` / `transferFromWithMemo` and must run after the zero-actor checks and before the transfer-side policies, so the canonical revert order stays pause → zero-receiver → zero-sender → allowance → policies → balance.

### Alternative — fold pause, zero-actor, and allowance into `_transfer`

This option would move every remaining transfer-family check into the helper. It was rejected because allowance is entrypoint-specific. Folding it in would require a consume-allowance flag, and moving zero-actor checks after allowance would change revert order. This change only relocates the executor policy check.

### Alternative — keep the check in `transferFrom` only, add it to `transfer` separately

This option would add a matching check to `transfer` while leaving the existing `transferFrom` check, including its `msg.sender != from` carve-out, in place. It was rejected because it does not close the self-`transferFrom` bypass: a holder could still route around an executor allowlist by calling `transferFrom(self, to, amount)` instead of `transfer`. It also keeps the check duplicated across two entrypoints instead of centralized in `_transfer`.

## Migration Steps

This change is not breaking for a token that never configured `TRANSFER_EXECUTOR_POLICY`. The unset policy slot stays always-allow, and the factory bootstrap bypass is unchanged, so existing deployments and initialization flows are unaffected.

This change is breaking for a token that has already set a restrictive `TRANSFER_EXECUTOR_POLICY` and relied on either of the closed bypasses:

1. If holders were moving their own tokens with `transfer`, they must now be authorized under `TRANSFER_EXECUTOR_POLICY` (directly, or through a policy they belong to) to keep doing so.
2. If holders were relying on `msg.sender == from` to skip the check in `transferFrom`, the same authorization requirement now applies to that self-call path.

An issuer who wants to keep allowing holders to self-initiate transfers should add those holders, or a policy covering them, to the executor allowlist before this change activates.
