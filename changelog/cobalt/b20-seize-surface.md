# B20 — Beryl to Cobalt: seize surface + `burnBlocked` deprecation

> **Audience:** teams integrated against the base B20 surface on **Beryl** (live today) that
> perform administrative balance removal — today via the deprecated `burnBlocked`. This note covers
> **only** the seize surface landing at the **Cobalt** hardfork and what it means for `burnBlocked`.
> The surface is shared, so it applies to **both** B20 Asset and B20 Stablecoin.

## Summary

At Cobalt the base B20 surface gains a first-class **seize** operation: `seizeWithMemo(from, to,
amount, memo)` reassigns a holder's balance to a destination in one admin call, gated by a new
`SEIZE_ROLE`, a new `SEIZE` pause vector, and two new policy slots (`SEIZE_HOLDER_POLICY`,
`SEIZE_RECEIVER_POLICY`). **Nothing you call today breaks.** Every Beryl selector, event topic, and
error keeps its exact 4-byte selector / topic0 and stays dialable at Cobalt. In particular
`burnBlocked` is **deprecated but unchanged** — same selector, same events, same behavior — and
remains callable. The migration is: move administrative balance removal from `burnBlocked` to
`seizeWithMemo` (seize to a treasury/self address, then `burn` if you want the supply destroyed).
**Cobalt is not live yet**; until it activates only the Beryl surface exists on-chain, and every
`seize*`/`SEIZE_*` selector below is undialable.

## Mapping table

Selectors and topic0s below are the real values from the frozen ABIs
(`crates/common/precompiles/src/common/abi/v1.rs` = Beryl,
`crates/common/precompiles/src/common/abi/v2.rs` = Cobalt); all Beryl symbols keep their selector at
Cobalt. Seize lives on the shared `IB20` surface, so it is identical across Asset and Stablecoin.

### Functions

| Beryl symbol (selector) | Cobalt (selector) | Status | Why |
| --- | --- | --- | --- |
| `burnBlocked(address,uint256)` `0xec0cf3dc` | `burnBlocked(address,uint256)` `0xec0cf3dc` | deprecated-dialable | Retained unchanged for back-compat; prefer `seizeWithMemo` then `burn`. Destroys supply; reads `TRANSFER_SENDER_POLICY`. |
| `BURN_BLOCKED_ROLE()` `0x32ad9be8` | `BURN_BLOCKED_ROLE()` `0x32ad9be8` | carried over unchanged | Still gates `burnBlocked` only. |
| — | `seizeWithMemo(address,address,uint256,bytes32)` `0xf916d81b` | new | Admin balance reassignment (a transfer, not a burn). |
| — | `SEIZE_ROLE()` `0x3c7e9ba5` | new | Required to call `seizeWithMemo`. Value `keccak256("SEIZE_ROLE")` = `0x3469b8b0d89e9604f8510ed143f74a8336d22955d4f83e23bf53d9414e27f432`. |
| — | `SEIZE_HOLDER_POLICY()` `0xb279d311` | new | Policy slot consulted against `from`. Value `keccak256("SEIZE_HOLDER_POLICY")` = `0x1497ab2b67ebb0a75dd9cdd6aec9f0e64620e6b87e911af7a088ac12e58d9ef2`. |
| — | `SEIZE_RECEIVER_POLICY()` `0xb31da27f` | new | Policy slot consulted against `to`. Value `keccak256("SEIZE_RECEIVER_POLICY")` = `0xbf15b19caf5c77422c038bc25f26b8b815c3a14f6d04c6616076b81bcfe07b3d`. |

### Events

| Beryl event (topic0) | Cobalt (topic0) | Status | Why |
| --- | --- | --- | --- |
| `BurnedBlocked(address,address,uint256)` `0x0b552e96653fd6842da37c477005d3b5c08a8c7d3631b1f43787b2dc9a1006a3` | unchanged | deprecated-still-emitted | Still emitted by `burnBlocked` alongside `Transfer(from, address(0), amount)`. |
| — | `Seized(address,address,address,uint256)` `0xa9aec5d8b86e2fa2fd6ac3af62f2622e3dfdab1967d4cbbb56a5df7d74cb887c` | new | Emitted by `seizeWithMemo` after `Transfer(from, to, amount)` and `Memo(caller, memo)`. |

### Errors

| Beryl error (selector) | Cobalt (selector) | Status | Why |
| --- | --- | --- | --- |
| `AccountNotBlocked(address)` `0x64a5cb46` | unchanged | present on Beryl already | Thrown by `burnBlocked` when `from` is authorized under `TRANSFER_SENDER_POLICY` (i.e. not blocked). |
| — | `AccountNotSeizable(address)` `0x91dbbc8d` | new | Thrown by `seizeWithMemo` when `from` is authorized under `SEIZE_HOLDER_POLICY` (i.e. not seizable). |

### Pause features

`PausableFeature` is append-only; Cobalt adds one ordinal.

| Beryl ordinals | Cobalt addition | Storage bit | Why |
| --- | --- | --- | --- |
| `TRANSFER=0`, `MINT=1`, `BURN=2` | `SEIZE=3` | `1 << 3 = 8` | Independent pause vector for `seizeWithMemo`. `ALL_FEATURES_PAUSED` becomes `15` (`0b1111`). |

`seizeWithMemo` is gated by the new `SEIZE` vector — **not** `BURN`. `burnBlocked` stays under `BURN`.

## New at Cobalt (adopt these)

### `seizeWithMemo(from, to, amount, memo)`

The canonical administrative balance-removal path. It is a **transfer** (balance moves `from -> to`;
`totalSupply` is unchanged), performed as an admin op that **skips allowance and the transfer
policies** (`TRANSFER_SENDER/RECEIVER/EXECUTOR_POLICY`). Emits, in order:

1. `Transfer(from, to, amount)`
2. `Memo(caller, memo)` — a memo of `bytes32(0)` is permitted
3. `Seized(caller, from, to, amount)`

Requirements and guards:

- **Role:** caller holds `SEIZE_ROLE` (else `AccessControlUnauthorizedAccount`).
- **Pause:** `SEIZE` not paused (else `ContractPaused(SEIZE)`).
- **Addresses:** `to != address(0)` and `from != to` (else `InvalidReceiver`); `from != address(0)`
  (else `InvalidSender`).
- **Holder gate:** `from` must be **blocked** under `SEIZE_HOLDER_POLICY` — that is, *not* authorized
  by it (else `AccountNotSeizable`). An **unset** slot reads as always-allow, so **no account is
  seizable until an issuer configures `SEIZE_HOLDER_POLICY`.**
- **Destination gate:** `to` must be authorized under `SEIZE_RECEIVER_POLICY`, which mirrors
  `MINT_RECEIVER_POLICY` — always enforced, but an **unset** slot is always-allow, so a token may
  seize to any destination (a treasury need not be allowlisted) until the slot is set.
- **Balance:** `from`'s balance >= `amount` (else `InsufficientBalance`).

Precedence when multiple guards would fail: holder gate > destination gate > balance
(`AccountNotSeizable` before `PolicyForbids(SEIZE_RECEIVER_POLICY, ...)` before
`InsufficientBalance`).

## `burnBlocked` is deprecated (but unchanged and still dialable)

`burnBlocked(from, amount)` keeps working exactly as on Beryl:

- Destroys `amount` from a `from` **blocked under `TRANSFER_SENDER_POLICY`**, without spending an
  allowance. Emits `Transfer(from, address(0), amount)` and `BurnedBlocked(caller, from, amount)`
  (no `Memo`).
- Gated by `BURN_BLOCKED_ROLE` and the `BURN` pause vector.
- Reverts `AccountNotBlocked` when `from` is authorized under `TRANSFER_SENDER_POLICY`.

To migrate, replace a `burnBlocked(from, amount)` with `seizeWithMemo(from, treasury, amount, memo)`
followed by `burn(amount)` from the treasury if you still want the supply destroyed. Note this
crosses two policy/role/pause domains (see edge cases) — it is not a drop-in selector swap.

## Guarantees / edge cases

**Q: Does seize change `totalSupply`? Is it a burn?**
No. Seize is a transfer: it reassigns `amount` from `from` to `to` and leaves `totalSupply`
untouched. `burnBlocked` is the burn — it sends to `address(0)` and reduces supply. To reproduce the
old burn-blocked outcome, seize to a treasury/self address and then `burn`.

**Q: `seizeWithMemo` and `burnBlocked` both target "bad" accounts — do they read the same set?**
No, and this is deliberate. `seizeWithMemo` reads `SEIZE_HOLDER_POLICY`; `burnBlocked` reads
`TRANSFER_SENDER_POLICY`. A token can define a "seizable" set distinct from its transfer-blocked
set. In both cases "eligible" means **not authorized** by the relevant policy, and an unset policy
(always-allow) means **nobody** is eligible.

**Q: Can I pause seize without pausing burns (or vice versa)?**
Yes. `SEIZE` (ordinal 3) and `BURN` (ordinal 2) are independent pause bits. Pausing `BURN` does not
stop `seizeWithMemo`, and pausing `SEIZE` does not stop `burn`/`burnWithMemo`/`burnBlocked`.

**Q: Do `SEIZE_ROLE` and `BURN_BLOCKED_ROLE` overlap?**
No. `seizeWithMemo` requires `SEIZE_ROLE`; `burnBlocked` requires `BURN_BLOCKED_ROLE`. Granting one
does not grant the other.

**Q: I never configured the seize policies — what happens if I call `seizeWithMemo`?**
It reverts `AccountNotSeizable(from)` for every `from`: an unset `SEIZE_HOLDER_POLICY` is
always-allow, so no account is seizable. `SEIZE_HOLDER_POLICY` must be configured to designate
seizable holders before seize does anything. (`SEIZE_RECEIVER_POLICY` left unset simply permits any
destination.)

**Q: Does seize consult the transfer policies or spend an allowance?**
No. It is an admin op: it bypasses `TRANSFER_SENDER/RECEIVER/EXECUTOR_POLICY` and allowances, and
enforces only `SEIZE_HOLDER_POLICY` (on `from`) and `SEIZE_RECEIVER_POLICY` (on `to`).

**Q: Is seize available on B20 Stablecoin as well as B20 Asset?**
Yes. It is defined on the shared `IB20` surface, so both variants expose the identical
`seizeWithMemo` selector, `Seized` topic0, `AccountNotSeizable` selector, `SEIZE_*` getters, and
`SEIZE` pause bit at Cobalt.
