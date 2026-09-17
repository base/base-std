# Reject the Token as a Credit Recipient

- **Feature Name**: token_receiver
- **Start Date**: 2026-09-17
- **Authors**: Rayyan Alam
- **Title**: (Breaking) Reject the Token as a Credit Recipient

## Summary

This change rejects crediting a B20 balance to the token's own address. `transfer`, `transferFrom`, their memo variants, `mint`, `mintWithMemo`, `batchMint`, and `seizeWithMemo` revert `InvalidReceiver(address(this))` when `to` is the token.

Holder-to-holder self-transfers (`from == to` for a user) are unchanged. `seizeWithMemo` from the token address remains allowed so a balance already sitting at the token can be recovered to a treasury.

The change is purely behavioral. It adds no new selectors, events, errors, or storage.

## Motivation

A holder who sends tokens to the token address cannot move them back. The precompile has no code that can call `transfer` on its own behalf, so the credited balance is stuck unless an admin seizes it.

That is a preventable footgun. The same lock happens if an issuer mints or seizes to the token. Rejecting the token as a destination on every credit path closes the hole before the balance is written.

## Background

B20 already rejects `address(0)` as a destination with `InvalidReceiver`, matching OpenZeppelin ERC-6093. Seize additionally rejects `from == to` so a no-op reassignment cannot emit a misleading `Transfer` / `Memo` / `Seized` trail.

The token's own address is a third invalid destination. Unlike `address(0)`, which is a burn in ERC-20, crediting the token increases `balances[token]` and leaves `totalSupply` unchanged. There is no holder, and no ERC-20 call the token can make to spend that balance.

`seizeWithMemo` is an admin reassignment. It skips transfer policies and allowance. Using it with `from == address(this)` is the recovery path for balances that were credited to the token before this change activated.

Sending token A to a different B20 token B is out of scope. That check needs a cross-token registry and lives in the Rust implementation.

## Specs

### Interface Changes

This change adds no new functions, events, errors, or selectors. `InvalidReceiver(address receiver)` already exists. Its documented triggers now include `receiver == address(this)`.

### Behavioural Changes

A shared valid-receiver check runs at the same position as today's zero-receiver guard:

```solidity
if (to == address(0) || to == address(this)) revert InvalidReceiver(to);
```

Canonical order is unchanged. `address(0)` and `address(this)` are two triggers of the same invalid-receiver step; they cannot both be true.

- `transfer` / `transferWithMemo`: pause → **invalid-receiver** → zero-sender → executor policy → sender policy → receiver policy → balance.
- `transferFrom` / `transferFromWithMemo`: pause → **invalid-receiver** → zero-sender → allowance → executor policy → sender policy → receiver policy → balance.
- `mint` / `mintWithMemo`: pause → role → **invalid-receiver** → mint-receiver policy → supply cap.
- `batchMint`: pause → role → length / empty → per-element **invalid-receiver** → `_mint` body.
- `seizeWithMemo`: pause → role → **invalid-receiver** → zero-sender → self-seize (`from == to`) → seizable → seize-receiver policy → balance.

`from == address(this)` is not rejected. A seize that drains the token into a treasury still succeeds.

### Examples

A holder transfer to the token reverts:

```solidity
vm.prank(alice);
token.transfer(address(token), amount); // reverts InvalidReceiver(address(token))
```

Mint and seize to the token revert the same way:

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

### Chosen: reuse `InvalidReceiver`, check `to == address(this)` on every credit path

The destination is invalid for the same reason `address(0)` is invalid: the credited units cannot be spent by a holder. Reusing `InvalidReceiver` avoids a new selector and keeps revert handling unchanged for wallets that already treat that error as "do not send here".

Mint, seize, and `batchMint` are included because they write the same `balances[to]` slot. Leaving them open would recreate the lock through an admin path.

The check lives next to the existing zero-receiver guard, not inside `_moveBalance`. `_moveBalance` is an unguarded mechanic; callers already apply their own input checks. Putting the new condition there would change that contract.

### Alternative — new error such as `SelfSend(address)`

A dedicated error would make the token-address case obvious in traces. It was rejected because it adds ABI surface for a condition that is already "this destination is invalid", and because wallets would have to learn a second selector to block the same user mistake.

### Alternative — transfer-family only

Restricting the check to `transfer` / `transferFrom` would match the original holder-send incident and leave mint and seize able to lock supply. It was rejected because the stuck-balance outcome is the same on every credit path, and the recovery story (`seize` from the token) is clearer if no path can credit the token going forward.

### Alternative — also reject `from == address(this)`

Blocking spends from the token would close the only recovery path for balances already sitting there. It was rejected.

## Migration Steps

Wallets, custodians, and indexers should treat the token address as an invalid recipient, the same way they already treat `address(0)`. A transfer, mint, or seize to that address that succeeded before Denim will revert `InvalidReceiver` after activation.

Balances already credited to a token address before activation stay there. Recover them with `seizeWithMemo(token, treasury, amount, memo)` (the token must be seizable under `SEIZE_EXEMPT_POLICY`, and the caller must hold `SEIZE_ROLE`).

This change does not affect holder-to-holder self-transfers, approvals, or burns.
