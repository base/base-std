# ISO 4217 Currency Filter

How the `B20Stablecoin` variant decides which `currency` strings to accept, and why the scope is narrower than "stablecoin" colloquially suggests.

- The filter validates `B20Stablecoin.currency` at creation against a hardcoded allowlist in [`src/utils/ISO4217.sol`](../src/utils/ISO4217.sol).
- Scope: active ISO 4217 alphabetic codes for **circulating national fiat currencies only** (~150 codes).
- Aligns with **MiCA E-Money Tokens** and **MAS Single-Currency Stablecoins**; narrower than the broader **FSB** (Financial Stability Board) and **BIS** (Bank for International Settlements) definition that includes commodities, baskets, and crypto pegs.
- `currency` is **self-declared** — the filter gates format and membership, not truthfulness; the token may not actually be backed by what it declares.
- Consumers using `currency()` for authorization or routing MUST add their own issuer/contract allowlist on top.
- The value is set at creation and is immutable; rejected inputs revert with `ITokenFactory.InvalidCurrency(code)` carrying the offending string verbatim.

## Inclusion / Exclusion

| Category | Status | Description | Codes |
| --- | --- | --- | --- |
| G10 + SGD | Included | Most-traded reserve currencies; MAS-anchored set | USD, EUR, JPY, GBP, AUD, NZD, CAD, CHF, NOK, SEK, SGD |
| Multi-country X-prefix fiat | Included | Real circulating fiat issued by supranational central banks (BCEAO, BEAC, ECCB, IEOM) | XOF, XAF, XCD, XPF |
| Precious metals | Excluded | Commodities, not means of payment — commodity-backed tokens belong on `B20Security` | XAU, XAG, XPT, XPD |
| European composite units | Excluded | Defunct supranational accounting units retained for historical reconciliation | XBA, XBB, XBC, XBD |
| Other supranational synthetics | Excluded | Reserve assets and regional units of account, not circulating currencies | XDR, XSU, XUA |
| Sentinels | Excluded | Reserved markers ("no currency" / test code), not currencies | XXX, XTS |
| Funds codes / indexing units | Excluded | Inflation-indexing devices, complementary currencies, and forex settlement conventions — not things one can hold or settle in | BOV, CHE, CHW, CLF, COU, MXV, USN, UYI, UYW |

- Crypto tickers and arbitrary strings are rejected by virtue of being off the ISO 4217 active list (no explicit entry needed).
- Per-entry rationale for each blocklist code lives inline in `ISO4217.excludedAt`.
- Any future Rust precompile implementation must mirror this allowlist and blocklist exactly.
