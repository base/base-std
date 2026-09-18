# Reject the Token Itself as a Credit Recipient

- **Feature Name**: token_receiver
- **Start Date**: 2026-09-17
- **Authors**: Rayyan Alam
- **Title**: (Breaking) Reject the Token Itself as a Credit Recipient

## Summary

Denim rejects crediting a B20 balance to the token's own address.

`transfer`, `transferFrom`, their memo variants, `mint`, `mintWithMemo`, `batchMint`, and `seizeWithMemo` revert `InvalidReceiver(to)` when `to == address(this)`. Holder-to-holder self-transfers (`from == to` for a user) still succeed. `seizeWithMemo` from the token address still succeeds, so an issuer can recover a balance already sitting at the token.

Sends between different B20 tokens are unaffected. The change is behavioral. It adds no new selectors, events, errors, or storage.

## Motivation

A B20 token is a precompile. It never acts as `msg.sender` on its own `transfer`. A holder cannot move a balance credited to the token's own address.

The reported failure mode is a paste error: a user targets the token address in a wallet UI and sends the token to itself. Before Denim the call succeeds and the units sit stuck at the token until an issuer seizes them.

Denim rejects that specific paste-error path at the token boundary. Issuer recovery through `seizeWithMemo` stays available so pre-activation stuck balances remain recoverable.

## Background

B20 is a native token precompile. The token address has no holder key and cannot initiate calls. A credit to that address is not spender-recoverable by the sender.

`InvalidReceiver(address receiver)` already fires for `address(0)` (ERC-6093). This change adds `address(this)` as a second trigger of the same error.

## Specs

### Interface Changes

This change adds no new functions, events, errors, or selectors. `InvalidReceiver(address receiver)` already exists. Its documented triggers now include the token's own address.

### Behavioural Changes

A shared valid-receiver check runs at the same position as the existing zero-receiver guard:

```solidity
if (to == address(0) || to == address(this)) revert InvalidReceiver(to);
```

Canonical order is unchanged. `address(0)` and `address(this)` are two triggers of the same invalid-receiver step. They cannot both be true for a real destination.

| Function | Check order |
| --- | --- |
| `transfer` / `transferWithMemo` | pause → **invalid-receiver** → zero-sender → executor policy → sender policy → receiver policy → balance |
| `transferFrom` / `transferFromWithMemo` | pause → **invalid-receiver** → zero-sender → allowance → executor policy → sender policy → receiver policy → balance |
| `mint` / `mintWithMemo` | pause → role → **invalid-receiver** → mint-receiver policy → supply cap |
| `batchMint` | pause → role → length / empty → per-element **invalid-receiver** → `_mint` body |
| `seizeWithMemo` | pause → role → **invalid-receiver** → zero-sender → self-seize (`from == to`) → seizable → seize-receiver policy → balance |

`from` may equal `address(this)`. A seize that drains the token into a treasury still succeeds.

### Examples

A holder transfer to this token reverts:

```solidity
vm.prank(alice);
token.transfer(address(token), amount); // reverts InvalidReceiver(address(token))
```

Mint and seize to the token address revert the same way:

```solidity
token.mint(address(token), amount); // reverts InvalidReceiver(address(token))
token.seizeWithMemo(alice, address(token), amount, memo); // reverts InvalidReceiver(address(token))
```

A holder sending to themselves still succeeds:

```solidity
vm.prank(alice);
token.transfer(alice, amount); // succeeds; balance and totalSupply unchanged
```

Recovery of a pre-activation stuck balance still succeeds:

```solidity
token.seizeWithMemo(address(token), treasury, amount, memo); // succeeds
```

## Design Decisions & Alternatives Considered

### Chosen: reuse `InvalidReceiver`, reject `to == address(this)` on every credit path

The destination is invalid for the same reason `address(0)` is invalid: a holder cannot spend the credited units. Reusing `InvalidReceiver` avoids a new selector. Wallets that already treat that error as "do not send here" keep the same revert handling.

The check compares against `address(this)` — one word, no external call, matches the reported paste-error footgun exactly. Mint, seize, and `batchMint` are included because they write the same `balances[to]` slot.

The check lives next to the existing zero-receiver guard, not inside `_moveBalance`. `_moveBalance` is an unguarded mechanic. Callers already apply their own input checks.

### Alternative — reject any B20-prefix address as recipient

That would extend the same protection to sends to *other* B20 tokens (token A → token B). It was rejected: the reported incident is a paste error against the token being called, not cross-token misrouting. Blocking cross-token credits also complicates settlement patterns where a B20 legitimately holds another B20 as an operational balance. Denim scopes the gate to the paste-error case; cross-token stuck credits remain recoverable via `seizeWithMemo`.

### Alternative — call `isB20Initialized(to)`

That would reject only live tokens. It was rejected because it adds a factory call on every credit path and does not fit the paste-error framing.

### Alternative — new error such as `SelfSend(address)`

A dedicated error would make the case obvious in traces. It was rejected because it adds ABI surface for a condition that is already "this destination is invalid".

### Alternative — also reject `from == address(this)`

Blocking spends from the token address would close the only recovery path for balances already sitting there. It was rejected.

## Migration Steps

1. Treat this token's own address as an invalid recipient, the same way you already treat `address(0)`. This applies to wallets, custodians, and indexers.
2. After Denim activation, expect `InvalidReceiver` from a transfer, mint, or seize to `address(token)` that succeeded before Denim.
3. If a balance is already credited to the token address from before activation, recover it with `seizeWithMemo(address(token), treasury, amount, memo)`. The token must be seizable under `SEIZE_EXEMPT_POLICY`. The caller must hold `SEIZE_ROLE`.
4. Do not change holder-to-holder self-transfers, approvals, burns, or sends to other B20 tokens. This change does not affect them.
