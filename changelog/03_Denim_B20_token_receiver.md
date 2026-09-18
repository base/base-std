# Reject B20-Prefix Addresses as Credit Recipients

- **Feature Name**: token_receiver
- **Start Date**: 2026-09-17
- **Authors**: Rayyan Alam
- **Title**: (Breaking) Reject B20-Prefix Addresses as Credit Recipients

## Summary

Denim rejects crediting a B20 balance to any B20-prefix address — a set that includes its own token and every other B20 token.

`transfer`, `transferFrom`, their memo variants, `mint`, `mintWithMemo`, `batchMint`, and `seizeWithMemo` revert `InvalidReceiver(to)` when `to` is a B20-prefix address. Holder-to-holder self-transfers (`from == to` for a user) still succeed. `seizeWithMemo` from a B20 address still succeeds, so an issuer can recover a balance already sitting at a token.

Credits to the factory (`0xB20f…`), the Policy Registry, and the Activation Registry still succeed. Those addresses are not B20-prefix. The change is behavioral. It adds no new selectors, events, errors, or storage.

## Motivation

A B20 token is a precompile. It never acts as `msg.sender` on its own `transfer`. A holder cannot move a balance credited to a token address.

Before Denim, a credit to this token or another B20 succeeds. Those units stay stuck for the holder until an issuer seizes them. A send to `address(this)` and a send to another B20 have the same holder-side outcome. The guard therefore covers the whole token prefix.

Issuer recovery through `seizeWithMemo` stays available. This change stops new stuck credits. It does not remove the recovery path.

## Background

B20 is a native token precompile. The token address has no holder key and cannot initiate calls. A credit to that address is not spender-recoverable by the sender.

Token address layout:

- Byte `[0]` is `0xB2`.
- Bytes `[1:9]` are zero.
- Byte `[10]` is the variant: Asset `0x00`, Stablecoin `0x01`.
- The remainder is derived from `(sender, salt)`.

`IB20Factory.isB20(address)` is this prefix check. It does not require the token to exist yet.

`InvalidReceiver(address receiver)` already fires for `address(0)` (ERC-6093). This change adds B20-prefix destinations as a second trigger of the same error.

## Specs

### Interface Changes

This change adds no new functions, events, errors, or selectors. `InvalidReceiver(address receiver)` already exists. Its documented triggers now include any B20-prefix address.

### Behavioural Changes

A shared valid-receiver check runs at the same position as the existing zero-receiver guard:

```solidity
if (to == address(0) || _isB20Prefix(to)) revert InvalidReceiver(to);
// _isB20Prefix: (uint160(to) >> 80) == (uint160(0xB2) << 72)
```

Canonical order is unchanged. `address(0)` and a B20-prefix address are two triggers of the same invalid-receiver step. They cannot both be true for a real destination.

| Function | Check order |
| --- | --- |
| `transfer` / `transferWithMemo` | pause → **invalid-receiver** → zero-sender → executor policy → sender policy → receiver policy → balance |
| `transferFrom` / `transferFromWithMemo` | pause → **invalid-receiver** → zero-sender → allowance → executor policy → sender policy → receiver policy → balance |
| `mint` / `mintWithMemo` | pause → role → **invalid-receiver** → mint-receiver policy → supply cap |
| `batchMint` | pause → role → length / empty → per-element **invalid-receiver** → `_mint` body |
| `seizeWithMemo` | pause → role → **invalid-receiver** → zero-sender → self-seize (`from == to`) → seizable → seize-receiver policy → balance |

`from` may be a B20 address. A seize that drains a token into a treasury still succeeds.

### Examples

A holder transfer to this token or another B20 reverts:

```solidity
vm.prank(alice);
token.transfer(address(token), amount); // reverts InvalidReceiver(address(token))

vm.prank(alice);
token.transfer(address(otherB20), amount); // reverts InvalidReceiver(address(otherB20))
```

Mint and seize to a B20 address revert the same way:

```solidity
token.mint(address(token), amount); // reverts InvalidReceiver(address(token))
token.seizeWithMemo(alice, address(otherB20), amount, memo); // reverts InvalidReceiver(address(otherB20))
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

### Chosen: reuse `InvalidReceiver`, reject any B20-prefix `to` on every credit path

The destination is invalid for the same reason `address(0)` is invalid: a holder cannot spend the credited units. Reusing `InvalidReceiver` avoids a new selector. Wallets that already treat that error as "do not send here" keep the same revert handling.

A pure prefix check matches the token address layout. It covers this token and every other B20 without an external call. Mint, seize, and `batchMint` are included because they write the same `balances[to]` slot.

The check lives next to the existing zero-receiver guard, not inside `_moveBalance`. `_moveBalance` is an unguarded mechanic. Callers already apply their own input checks.

Credits to the factory (`0xB20f…`), the Policy Registry, and the Activation Registry still succeed. Those addresses are not B20-prefix. The problem this change addresses is a send to a token address, not a send to a well-known singleton. Issuer recovery of a balance already at a B20 token remains `seizeWithMemo` with `from` set to that token.

### Alternative — only reject `to == address(this)`

That closes the original self-send incident but leaves token A → token B open. It was rejected because the stuck-balance outcome is the same for every B20 destination.

### Alternative — call `isB20Initialized(to)`

That would reject only live tokens and allow uncreated predicted addresses. It was rejected because it adds a factory call on every credit path. An uncreated B20-prefix address is still not a useful recipient.

### Alternative — new error such as `SelfSend(address)`

A dedicated error would make the case obvious in traces. It was rejected because it adds ABI surface for a condition that is already "this destination is invalid".

### Alternative — also reject B20-prefix `from`

Blocking spends from a B20 address would close the only recovery path for balances already sitting there. It was rejected.

## Migration Steps

1. Treat any B20-prefix address as an invalid recipient, the same way you already treat `address(0)`. This applies to wallets, custodians, and indexers.
2. After Denim activation, expect `InvalidReceiver` from a transfer, mint, or seize to a B20-prefix address that succeeded before Denim.
3. If a balance is already credited to a token address from before activation, recover it with `seizeWithMemo(token, treasury, amount, memo)`. The token must be seizable under `SEIZE_EXEMPT_POLICY`. The caller must hold `SEIZE_ROLE`.
4. Do not change holder-to-holder self-transfers, approvals, or burns. This change does not affect them.
