# Currency Validation

How the `B20Stablecoin` variant constrains its `currency` field at creation, and why the chosen filter is a permissive format check rather than a curated allowlist.

## Problem

The `B20Stablecoin` variant declares an immutable `currency` identifier at creation. Without any constraint on what issuers can pass:

- Two issuers might use `"USD"` and `"usd"` for the same currency, breaking any consumer that groups by the field.
- An issuer might pass their token's symbol (`"USDC"`) instead of a currency code.
- Empty strings or numeric / punctuation junk could end up persisted in `currency()` forever.

The factory needs a deterministic, machine-readable filter rather than a free-form string.

## Solution

Validate `currency` at creation as **exactly three uppercase ASCII letters (`A`–`Z`)**, implemented in [`test/lib/ISO4217.sol`](../../../test/lib/ISO4217.sol). Anything failing the format check reverts with `IB20Factory.InvalidCurrency(code)` carrying the offending string verbatim.

Format only — **membership in the ISO 4217 register is not enforced on-chain.** Any 3-letter uppercase string is accepted, including codes that are not on ISO 4217 at all.

Key properties:

- Set at creation by the factory; immutable thereafter.
- Self-declared — the filter gates shape, not truthfulness or even existence as a real currency.
- Any consumer using `currency()` for authorization or routing MUST add its own issuer / contract allowlist on top.

## Why format-only

Earlier iterations of this validation maintained a curated allowlist of active ISO 4217 alphabetic codes for circulating national fiat currencies (excluding metals, sentinels, funds codes, supranational synthetic units, etc.). That approach has been removed in favor of the simple format check. Reasons:

| Concern with the allowlist | Why it pushed us off the allowlist |
| --- | --- |
| **Maintenance overhead.** ISO 4217 publishes amendments on the order of once per year. Each amendment requires a code change in lockstep across the Solidity reference and any Rust precompile implementation. Examples just in the last year: ANG (Netherlands Antillean Guilder) withdrawn 2025-03-31 and replaced by XCG; BGN withdrawn 2026-01-01 when Bulgaria adopted the euro. | The Solidity / Rust lockstep requirement is a recurring tax on a non-core surface. |
| **Backwards-compat ambiguity.** When ISO withdraws a code, real balances often remain in circulation for years. There's no clean answer to "drop the code on the date ISO says" vs. "keep the code while supply persists" — both have costs, and both require ongoing judgement. | Format-only sidesteps the question entirely. |
| **Self-declared anyway.** The filter never asserted that the issuer's reserves actually back the declared currency. Any protocol routing or authorizing on `currency()` already had to layer its own issuer / contract allowlist on top of the ISO check. | The ISO check was never the trust signal; consumer-side allowlists are. Removing the ISO check removes redundant work, not real validation. |
| **Coverage gaps.** Basket-pegged stablecoins, algorithmic non-pegged stable assets, and commodity-backed tokens marketed as stablecoins all have no clean home under a fiat-only allowlist — they'd need separate variants or carve-outs. | A permissive format check lets the consumer-side allowlists decide what categories they care about, instead of baking those decisions into an immutable precompile. |

The format check still catches the typo / shape errors the original problem statement called out (`"usd"`, `"USDC"`, empty string, wrong length, digits, symbols) — those were always the cheap-to-catch failures, and we still catch them.

## Risks and mitigations

| Concern | Mitigation |
| --- | --- |
| `currency = "ZZZ"` or `"XYZ"` is now accepted even though no such currency exists | The on-chain field is self-declared; this was already the case at the protocol level. Consumer-side allowlists are responsible for asserting the declared currency is one they recognize. |
| Commodity-backed tokens (PAXG, XAUT, AABBG) can now declare `currency = "XAU"` and pass validation | They still belong on the `B20Security` variant for structural reasons (claims on a vault) — a permissive `currency` check on the Stablecoin variant doesn't change the variant choice. Consumer-side categorization is unchanged. |
| Two issuers might still pick incompatible identifiers for the same underlying asset (e.g. `"USD"` vs. a hypothetical `"US$"`) | The format check rules out the second example (symbols), and conventional ISO 4217 codes are the obvious schelling point for the first. Standardization is now norms-driven rather than enforced. |
| Adding richer validation later (e.g. an explicit blocklist for sentinels) would require a precompile change | True, but the same was true under the allowlist — and the format-only baseline makes additive policy easier than starting from a curated set. |

## Alternatives considered

| Option | Pros | Cons |
| --- | --- | --- |
| **No validation**<br>Accept any non-empty string for `currency` | • Simplest possible impl<br>• Zero maintenance | • Typos (`"usd"`, `"USDC"`) pollute the value space<br>• Empty strings and arbitrary junk silently persist |
| **Format-only check** *(chosen)*<br>Length 3 + uppercase ASCII; no membership check | • Cheap<br>• No allowlist to maintain<br>• Catches obvious garbage<br>• Same precompile contract whether ISO 4217 changes or not | • Admits `"ZZZ"`, `"BTC"`, `"ETH"`, etc. — semantic validity pushed to consumer-side allowlists |
| **Full ISO 4217 active list**<br>Every alphabetic code, incl. X-prefix metals, supranational synthetics, funds codes | • Matches the official standard literally<br>• Familiar to FX-adjacent tooling | • Includes commodities (belong on `B20Security`)<br>• Includes funds codes (CLF, USN — not holdable)<br>• Annual maintenance + Rust precompile lockstep |
| **Narrow ISO 4217 fiat allowlist**<br>Circulating national fiat only; MiCA EMT / MAS SCS aligned | • Regulatory-category alignment<br>• Commodities pushed to `B20Security` | • Allowlist maintenance (~1/year)<br>• ISO amendments need lockstep Rust impl change<br>• Backwards-compat ambiguity on withdrawn codes (ANG, BGN) requires per-incident judgement<br>• Self-declared anyway — doesn't substitute for consumer-side allowlists |
