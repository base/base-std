# Reject the Token Itself as a Credit Recipient

- **Feature Name**: token_receiver
- **Start Date**: 2026-09-17
- **Authors**: Rayyan Alam
- **Title**: (Breaking) Reject the Token Itself as a Credit Recipient

## Summary

Denim rejects a send whose destination is this token's own address. That destination cannot spend the credited tokens, so the send would lock them.

`transfer`, `transferFrom`, their memo variants, `mint`, `mintWithMemo`, `batchMint`, and `seizeWithMemo` revert `InvalidReceiver(to)` when `to` is the token. A holder sending to themselves (`from == to`) still succeeds. An issuer can still recover tokens already credited to the token: `seizeWithMemo` from the token address succeeds.

## Motivation

Users sometimes send tokens to the token's own address. Wallet UX makes that address easy to select, and copy or paste mistakes send to it as well.

A B20 token is a precompile. It has no holder key and cannot call `transfer` on itself. After a transfer lands at the token address, the sender cannot recover those tokens. Only the issuer can, by calling `seizeWithMemo`.

There is no valid use case for crediting this token to its own address. Denim therefore reverts `InvalidReceiver(to)` on that destination so the accidental send fails instead of locking the funds.

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


| Function                                | Check order                                                                                                                |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `transfer` / `transferWithMemo`         | pause → **invalid-receiver** → zero-sender → executor policy → sender policy → receiver policy → balance                   |
| `transferFrom` / `transferFromWithMemo` | pause → **invalid-receiver** → zero-sender → allowance → executor policy → sender policy → receiver policy → balance       |
| `mint` / `mintWithMemo`                 | pause → role → **invalid-receiver** → mint-receiver policy → supply cap                                                    |
| `batchMint`                             | pause → role → length / empty → per-element **invalid-receiver** → `_mint` body                                            |
| `seizeWithMemo`                         | pause → role → **invalid-receiver** → zero-sender → self-seize (`from == to`) → seizable → seize-receiver policy → balance |


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

That would also revert when `to` is a different B20-prefix address (token A → token B). It was rejected. A prefix check cannot tell a B20 token from a user-controlled account in that address space, such as a multisig. Rejecting the whole prefix would revert valid transfers to those recipients.

Denim therefore compares `to` against `address(this)` only. Sends to other addresses, including other B20 tokens, still succeed.

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

