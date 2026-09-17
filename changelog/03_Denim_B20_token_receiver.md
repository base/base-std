# Reject B20-Prefix Addresses as Credit Recipients

- **Feature Name**: token_receiver
- **Start Date**: 2026-09-17
- **Authors**: Rayyan Alam
- **Title**: (Breaking) Reject B20-Prefix Addresses as Credit Recipients

## Summary

This change rejects crediting a B20 balance to any address that matches the B20 factory address prefix (byte `[0] = 0xB2`, bytes `[1:10]` zero). `transfer`, `transferFrom`, their memo variants, `mint`, `mintWithMemo`, `batchMint`, and `seizeWithMemo` revert `InvalidReceiver(to)` when `to` is this token or any other B20-layout address.

Holder-to-holder self-transfers (`from == to` for a user) are unchanged. `seizeWithMemo` from a B20 address remains allowed so a balance already sitting at a token can be recovered to a treasury.

The change is purely behavioral. It adds no new selectors, events, errors, or storage.

## Motivation

A holder who sends tokens to a B20 token address cannot move them back. The precompile has no code that can call `transfer` on its own behalf, so the credited balance is stuck unless an admin seizes it.

That footgun exists for this token and for every other B20. Minting or seizing to a B20 address locks supply the same way. Rejecting every B20-prefix destination on every credit path closes the hole before the balance is written.

## Background

B20 already rejects `address(0)` as a destination with `InvalidReceiver`, matching OpenZeppelin ERC-6093. Seize additionally rejects `from == to` so a no-op reassignment cannot emit a misleading `Transfer` / `Memo` / `Seized` trail.

Every B20 token address is allocated by the factory with a fixed layout: byte `[0] = 0xB2`, bytes `[1:10]` zero, byte `[10]` the variant discriminant, and a salt-derived tail. That prefix is unique to B20 tokens. Checking it is a pure bit test — no factory call and no initialized-marker lookup.

Uncreated predicted addresses that match the same prefix also revert. Those destinations cannot spend either, so rejecting them is acceptable.

`seizeWithMemo` is an admin reassignment. It skips transfer policies and allowance. Using it with `from` equal to a B20 address is the recovery path for balances that were credited to a token before this change activated.

## Specs

### Interface Changes

This change adds no new functions, events, errors, or selectors. `InvalidReceiver(address receiver)` already exists. Its documented triggers now include any B20-prefix address.

### Behavioural Changes

A shared valid-receiver check runs at the same position as today's zero-receiver guard:

```solidity
if (to == address(0) || _isB20Prefix(to)) revert InvalidReceiver(to);
// _isB20Prefix: (uint160(to) >> 80) == (uint160(0xB2) << 72)
```

Canonical order is unchanged. `address(0)` and a B20-prefix address are two triggers of the same invalid-receiver step; they cannot both be true for a real destination.

- `transfer` / `transferWithMemo`: pause → **invalid-receiver** → zero-sender → executor policy → sender policy → receiver policy → balance.
- `transferFrom` / `transferFromWithMemo`: pause → **invalid-receiver** → zero-sender → allowance → executor policy → sender policy → receiver policy → balance.
- `mint` / `mintWithMemo`: pause → role → **invalid-receiver** → mint-receiver policy → supply cap.
- `batchMint`: pause → role → length / empty → per-element **invalid-receiver** → `_mint` body.
- `seizeWithMemo`: pause → role → **invalid-receiver** → zero-sender → self-seize (`from == to`) → seizable → seize-receiver policy → balance.

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

The destination is invalid for the same reason `address(0)` is invalid: the credited units cannot be spent by a holder. Reusing `InvalidReceiver` avoids a new selector and keeps revert handling unchanged for wallets that already treat that error as "do not send here".

A pure prefix check matches the factory address layout and covers this token and every other B20 without an external call. Mint, seize, and `batchMint` are included because they write the same `balances[to]` slot.

The check lives next to the existing zero-receiver guard, not inside `_moveBalance`. `_moveBalance` is an unguarded mechanic; callers already apply their own input checks.

### Alternative — only reject `to == address(this)`

That closes the original self-send incident but leaves token A → token B open. It was rejected because the stuck-balance outcome is the same for every B20 destination.

### Alternative — call `isB20Initialized(to)`

That would reject only live tokens and allow uncreated predicted addresses. It was rejected because it adds a factory call on every credit path, and an uncreated B20-prefix address is still not a useful recipient.

### Alternative — new error such as `SelfSend(address)`

A dedicated error would make the case obvious in traces. It was rejected because it adds ABI surface for a condition that is already "this destination is invalid".

### Alternative — also reject B20-prefix `from`

Blocking spends from a B20 address would close the only recovery path for balances already sitting there. It was rejected.

## Migration Steps

Wallets, custodians, and indexers should treat any B20-prefix address as an invalid recipient, the same way they already treat `address(0)`. A transfer, mint, or seize to such an address that succeeded before Denim will revert `InvalidReceiver` after activation.

Balances already credited to a token address before activation stay there. Recover them with `seizeWithMemo(token, treasury, amount, memo)` (the token must be seizable under `SEIZE_EXEMPT_POLICY`, and the caller must hold `SEIZE_ROLE`).

This change does not affect holder-to-holder self-transfers, approvals, or burns.
