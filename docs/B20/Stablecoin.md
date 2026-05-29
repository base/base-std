# B20 Stablecoin

The Stablecoin variant of B20. Everything in [B20/README.md](README.md) applies; this page covers the deltas only. See [`IB20Stablecoin`](../../src/interfaces/IB20Stablecoin.sol) for the Solidity interface.

## Fixed Decimals (6)

`decimals()` is hard-wired to `6`. The choice matches existing popular stablecoins.

## Currency Codes

`currency()` returns the ISO-style currency code as a `string` (e.g., `"USD"`, `"EUR"`). It is set once via `B20StablecoinCreateParams.currency` at creation, immutable thereafter, and restricted to `A`–`Z` bytes (no lowercase, no digits, no separators).

The value is **self-declared** — the contract does not verify it against any registry or allowlist. Wallets and indexers can use it to group stablecoins by underlying fiat without an external lookup, but it is not a proof of fiat backing.
