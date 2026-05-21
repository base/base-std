# Currency Validation

How the `B20Stablecoin` variant constrains its `currency` field at creation, and why the chosen filter is scoped narrower than "stablecoin" colloquially suggests.

## Problem

The `B20Stablecoin` variant declares an immutable `currency` identifier at creation. Without a constraint on what issuers can pass:

- Two issuers might use `"USD"` and `"usd"` for the same currency, breaking any consumer that groups by the field.
- An issuer might pass their token's symbol (`"USDC"`) instead of a currency code.
- Tokens claiming non-currency assets (gold, crypto, governance tokens) would all coexist under the same variant, polluting any tooling that categorizes by `currency()`.

The factory needs a deterministic, machine-readable filter rather than a free-form string.

## Solution

Validate `currency` at creation against a hardcoded allowlist of active **ISO 4217 alphabetic codes** for circulating national fiat currencies, implemented in [`src/utils/ISO4217.sol`](../../../src/utils/ISO4217.sol). Anything off the list reverts with `ITokenFactory.InvalidCurrency(code)` carrying the offending string verbatim.

Scope aligns with **MiCA E-Money Tokens** and **MAS Single-Currency Stablecoins** — narrower than the broader **FSB** (Financial Stability Board) and **BIS** (Bank for International Settlements) definition that includes commodities, baskets, and crypto pegs.

Key properties:

- Set at creation by the factory; immutable thereafter.
- Self-declared — the filter gates format and membership, not truthfulness.
- Any consumer using `currency()` for authorization or routing MUST add its own issuer/contract allowlist on top.

## Specification

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

## Risks and mitigations

| Concern | Mitigation |
| --- | --- |
| Commodity-backed tokens marketed as stablecoins (PAXG, XAUT, AABBG) will not be admitted here | These are structurally claims on a vault — securities-shaped instruments. They belong on the `B20Security` variant. |
| Crypto-collateralized stablecoins (DAI, LUSD, crvUSD) appear to be excluded | They fit this variant fine. The backing mechanism (custodial reserves, on-chain collateral, T-bills) is irrelevant to `currency()`; what matters is the peg target. If a token pegs to USD, declare `"USD"`. |
| Basket-pegged tokens (historically Libra/Diem) and algorithmic non-pegged stable assets (Ampleforth, historically Terra UST) have no current B-20 home | Accepted trade-off. A future basket / ART variant or use of the `B20` Default variant with custom monetary policy would be the path, not relaxation of this variant. |
| The variant name "Stablecoin" carries broader industry connotations than its admitted set | Anchored in regulatory precedent — MiCA EMT, MAS SCS, and US payment-stablecoin legislative proposals all draw the same line. |
| The allowlist is self-declared, not a trust signal — an issuer can declare `currency = "USD"` without backing reserves | The factory enforces format and membership only. Any protocol consuming `currency()` for an authorization or routing decision MUST layer its own issuer/contract allowlist on top. The standardized identifier is what those consumer-side allowlists organize around, not a substitute for them. |
| Adding or removing an ISO 4217 code requires a contract change | Real but rare — ISO 4217 registrations happen on the order of once per year. Both the Solidity reference and any Rust precompile implementation must be updated in lockstep when changes do occur. |
