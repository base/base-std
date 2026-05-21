# Currency Validation

How the `B20Stablecoin` variant constrains its `currency` field at creation, and why the chosen filter is scoped narrower than "stablecoin" colloquially suggests.

## Problem

The `B20Stablecoin` variant declares an immutable `currency` identifier at creation. Without a constraint on what issuers can pass:

- Two issuers might use `"USD"` and `"usd"` for the same currency, breaking any consumer that groups by the field.
- An issuer might pass their token's symbol (`"USDC"`) instead of a currency code.
- Tokens claiming non-currency assets (gold, crypto, governance tokens) would all coexist under the same variant, polluting any tooling that categorizes by `currency()`.

The factory needs a deterministic, machine-readable filter rather than a free-form string.

## Solution

Validate `currency` at creation against a hardcoded allowlist of active **ISO 4217 alphabetic codes** for circulating national fiat currencies, implemented in [`test/lib/ISO4217.sol`](../../../test/lib/ISO4217.sol). Anything off the list reverts with `ITokenFactory.InvalidCurrency(code)` carrying the offending string verbatim.

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

## Supported currencies

All 155 codes on the allowlist, alphabetical by code.

| Code | Currency | Region / issuer |
| --- | --- | --- |
| AED | UAE Dirham | United Arab Emirates |
| AFN | Afghan Afghani | Afghanistan |
| ALL | Albanian Lek | Albania |
| AMD | Armenian Dram | Armenia |
| ANG | Netherlands Antillean Guilder | Curaçao, Sint Maarten |
| AOA | Angolan Kwanza | Angola |
| ARS | Argentine Peso | Argentina |
| AUD | Australian Dollar | Australia |
| AWG | Aruban Florin | Aruba |
| AZN | Azerbaijani Manat | Azerbaijan |
| BAM | Bosnia and Herzegovina Convertible Mark | Bosnia and Herzegovina |
| BBD | Barbadian Dollar | Barbados |
| BDT | Bangladeshi Taka | Bangladesh |
| BGN | Bulgarian Lev | Bulgaria |
| BHD | Bahraini Dinar | Bahrain |
| BIF | Burundian Franc | Burundi |
| BMD | Bermudian Dollar | Bermuda |
| BND | Brunei Dollar | Brunei |
| BOB | Bolivian Boliviano | Bolivia |
| BRL | Brazilian Real | Brazil |
| BSD | Bahamian Dollar | Bahamas |
| BTN | Bhutanese Ngultrum | Bhutan |
| BWP | Botswana Pula | Botswana |
| BYN | Belarusian Ruble | Belarus |
| BZD | Belize Dollar | Belize |
| CAD | Canadian Dollar | Canada |
| CDF | Congolese Franc | DR Congo |
| CHF | Swiss Franc | Switzerland, Liechtenstein |
| CNY | Chinese Yuan Renminbi | China |
| COP | Colombian Peso | Colombia |
| CRC | Costa Rican Colón | Costa Rica |
| CUP | Cuban Peso | Cuba |
| CVE | Cape Verdean Escudo | Cape Verde |
| CZK | Czech Koruna | Czech Republic |
| DJF | Djiboutian Franc | Djibouti |
| DKK | Danish Krone | Denmark, Greenland, Faroe Islands |
| DOP | Dominican Peso | Dominican Republic |
| DZD | Algerian Dinar | Algeria |
| EGP | Egyptian Pound | Egypt |
| ERN | Eritrean Nakfa | Eritrea |
| ETB | Ethiopian Birr | Ethiopia |
| EUR | Euro | Eurozone |
| FJD | Fijian Dollar | Fiji |
| FKP | Falkland Islands Pound | Falkland Islands |
| GBP | British Pound Sterling | United Kingdom |
| GEL | Georgian Lari | Georgia |
| GHS | Ghanaian Cedi | Ghana |
| GIP | Gibraltar Pound | Gibraltar |
| GMD | Gambian Dalasi | The Gambia |
| GNF | Guinean Franc | Guinea |
| GTQ | Guatemalan Quetzal | Guatemala |
| GYD | Guyanese Dollar | Guyana |
| HKD | Hong Kong Dollar | Hong Kong |
| HNL | Honduran Lempira | Honduras |
| HTG | Haitian Gourde | Haiti |
| HUF | Hungarian Forint | Hungary |
| IDR | Indonesian Rupiah | Indonesia |
| ILS | Israeli New Shekel | Israel |
| INR | Indian Rupee | India, Bhutan |
| IQD | Iraqi Dinar | Iraq |
| IRR | Iranian Rial | Iran |
| ISK | Icelandic Króna | Iceland |
| JMD | Jamaican Dollar | Jamaica |
| JOD | Jordanian Dinar | Jordan |
| JPY | Japanese Yen | Japan |
| KES | Kenyan Shilling | Kenya |
| KGS | Kyrgyzstani Som | Kyrgyzstan |
| KHR | Cambodian Riel | Cambodia |
| KMF | Comorian Franc | Comoros |
| KPW | North Korean Won | North Korea |
| KRW | South Korean Won | South Korea |
| KWD | Kuwaiti Dinar | Kuwait |
| KYD | Cayman Islands Dollar | Cayman Islands |
| KZT | Kazakhstani Tenge | Kazakhstan |
| LAK | Lao Kip | Laos |
| LBP | Lebanese Pound | Lebanon |
| LKR | Sri Lankan Rupee | Sri Lanka |
| LRD | Liberian Dollar | Liberia |
| LSL | Lesotho Loti | Lesotho |
| LYD | Libyan Dinar | Libya |
| MAD | Moroccan Dirham | Morocco |
| MDL | Moldovan Leu | Moldova |
| MGA | Malagasy Ariary | Madagascar |
| MKD | Macedonian Denar | North Macedonia |
| MMK | Burmese Kyat | Myanmar |
| MNT | Mongolian Tögrög | Mongolia |
| MOP | Macanese Pataca | Macau |
| MRU | Mauritanian Ouguiya | Mauritania |
| MUR | Mauritian Rupee | Mauritius |
| MVR | Maldivian Rufiyaa | Maldives |
| MWK | Malawian Kwacha | Malawi |
| MXN | Mexican Peso | Mexico |
| MYR | Malaysian Ringgit | Malaysia |
| MZN | Mozambican Metical | Mozambique |
| NAD | Namibian Dollar | Namibia |
| NGN | Nigerian Naira | Nigeria |
| NIO | Nicaraguan Córdoba | Nicaragua |
| NOK | Norwegian Krone | Norway |
| NPR | Nepalese Rupee | Nepal |
| NZD | New Zealand Dollar | New Zealand |
| OMR | Omani Rial | Oman |
| PAB | Panamanian Balboa | Panama |
| PEN | Peruvian Sol | Peru |
| PGK | Papua New Guinean Kina | Papua New Guinea |
| PHP | Philippine Peso | Philippines |
| PKR | Pakistani Rupee | Pakistan |
| PLN | Polish Złoty | Poland |
| PYG | Paraguayan Guaraní | Paraguay |
| QAR | Qatari Riyal | Qatar |
| RON | Romanian Leu | Romania |
| RSD | Serbian Dinar | Serbia |
| RUB | Russian Ruble | Russia |
| RWF | Rwandan Franc | Rwanda |
| SAR | Saudi Riyal | Saudi Arabia |
| SBD | Solomon Islands Dollar | Solomon Islands |
| SCR | Seychellois Rupee | Seychelles |
| SDG | Sudanese Pound | Sudan |
| SEK | Swedish Krona | Sweden |
| SGD | Singapore Dollar | Singapore |
| SHP | Saint Helena Pound | Saint Helena, Ascension |
| SLE | Sierra Leonean Leone | Sierra Leone |
| SOS | Somali Shilling | Somalia |
| SRD | Surinamese Dollar | Suriname |
| SSP | South Sudanese Pound | South Sudan |
| STN | São Tomé and Príncipe Dobra | São Tomé and Príncipe |
| SVC | Salvadoran Colón | El Salvador |
| SYP | Syrian Pound | Syria |
| SZL | Eswatini Lilangeni | Eswatini |
| THB | Thai Baht | Thailand |
| TJS | Tajikistani Somoni | Tajikistan |
| TMT | Turkmenistani Manat | Turkmenistan |
| TND | Tunisian Dinar | Tunisia |
| TOP | Tongan Paʻanga | Tonga |
| TRY | Turkish Lira | Turkey |
| TTD | Trinidad and Tobago Dollar | Trinidad and Tobago |
| TWD | New Taiwan Dollar | Taiwan |
| TZS | Tanzanian Shilling | Tanzania |
| UAH | Ukrainian Hryvnia | Ukraine |
| UGX | Ugandan Shilling | Uganda |
| USD | United States Dollar | United States (and El Salvador, Ecuador, Panama, others) |
| UYU | Uruguayan Peso | Uruguay |
| UZS | Uzbekistani Som | Uzbekistan |
| VED | Venezuelan Bolívar Digital | Venezuela |
| VES | Venezuelan Bolívar Soberano | Venezuela |
| VND | Vietnamese Đồng | Vietnam |
| VUV | Vanuatu Vatu | Vanuatu |
| WST | Samoan Tālā | Samoa |
| XAF | Central African CFA Franc | BEAC members (Cameroon, CAR, Chad, Congo, Equatorial Guinea, Gabon) |
| XCD | East Caribbean Dollar | ECCB members (Anguilla, Antigua, Dominica, Grenada, Montserrat, Saint Kitts and Nevis, Saint Lucia, Saint Vincent and the Grenadines) |
| XOF | West African CFA Franc | BCEAO members (Benin, Burkina Faso, Côte d'Ivoire, Guinea-Bissau, Mali, Niger, Senegal, Togo) |
| XPF | CFP Franc | French Pacific (French Polynesia, New Caledonia, Wallis and Futuna) |
| YER | Yemeni Rial | Yemen |
| ZAR | South African Rand | South Africa (and CMA: Eswatini, Lesotho, Namibia) |
| ZMW | Zambian Kwacha | Zambia |
| ZWG | Zimbabwe Gold | Zimbabwe |
