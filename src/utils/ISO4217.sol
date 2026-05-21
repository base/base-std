// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  ISO4217
/// @notice Helpers anchored in the ISO 4217 currency-code standard.
///         Currently exposes two primitives:
///         - `isValidFiatCode`: a static allowlist of active ISO 4217
///           alphabetic codes that correspond to **circulating national
///           fiat currencies**, used by the `TokenFactory` precompile
///           to validate the `currency` field passed to the STABLECOIN
///           variant of `createToken`.
///         - `excludedCount` / `excludedAt`: an enumerable record of
///           the ISO 4217 codes that are on the standard but
///           deliberately excluded from the fiat allowlist, with
///           inline comments explaining each exclusion. This makes the
///           rejected set readable as data rather than as the absence
///           of an entry, and lets tests fuzz over the blocklist to
///           prove every documented exclusion actually reverts.
///
///         The library scope is left intentionally broad so that
///         further ISO 4217 helpers (numeric-code lookup,
///         decimal-exponent lookup, etc.) can land in this file
///         without restructuring imports.
///
/// @dev    **Scope.** "Fiat" here means a currency that is issued by
///         a sovereign or supranational monetary authority and
///         circulates as a means of payment — i.e., something you can
///         hold and settle in. This is narrower than "every ISO 4217
///         alphabetic code": ISO 4217 also enumerates funds codes
///         (indexing units, internal accounting devices), bond-market
///         composite units, supranational synthetic reserve assets,
///         precious metals, and sentinel codes, none of which are
///         circulating currencies.
///
///         **The X-prefix is NOT a categorical exclusion rule.** ISO
///         4217 reserves the X-prefix for codes where no single ISO
///         3166 country code applies. That covers both "not a
///         currency" (metals, sentinels, synthetic units) AND
///         "currency shared across multiple countries by a
///         supranational central bank." The latter category contains
///         four real circulating fiat currencies used by tens of
///         millions of people, which the allowlist DOES include:
///         - `XOF` — CFA Franc BCEAO (8 West African states, BCEAO)
///         - `XAF` — CFA Franc BEAC (6 Central African states, BEAC)
///         - `XCD` — East Caribbean Dollar (8 Caribbean states, ECCB)
///         - `XPF` — CFP Franc (French Pacific territories)
///
///         **Why an allowlist at all.** `currency` is a self-declared,
///         immutable identifier. It is NOT a trust signal: a token can
///         declare any code without anyone checking that the token is
///         actually backed by the named currency. The allowlist
///         provides three concrete benefits regardless:
///           1. Standardized value space — every stablecoin's
///              `currency()` returns a code from one well-known
///              registry, so tooling can categorize the field without
///              having to parse free-form strings or invent its own
///              taxonomy.
///           2. Typo / garbage rejection at creation — `"usd"`,
///              `"USDT"`, `"US"`, `""` all revert at the factory rather
///              than silently shipping an unreadable identifier.
///           3. Forced design discussion for new categories — any
///              consumer that wants to ship tokens outside the fiat
///              category (commodity-backed, crypto-tracking, governance
///              tokens with stablecoin operational surface) is pushed
///              into the variant discussion rather than smuggling
///              through this field. The B-20 Security variant is the
///              intended home for commodity-backed tokens.
///
///         **What's excluded (enumerated by `excludedAt`).**
///         - **Precious metals** (XAU/XAG/XPT/XPD): commodities, not
///           means of payment. Commodity-backed tokens belong on the
///           Security variant.
///         - **European composite units** (XBA-XBD): defunct
///           supranational accounting units (EURCO, E.M.U.-6, E.U.A.-9,
///           E.U.A.-17). Retained on ISO 4217 for historical
///           reconciliation only.
///         - **Other supranational synthetic units** (XDR/XSU/XUA):
///           IMF Special Drawing Rights, Sucre, ADB Unit of Account.
///           Synthetic reserve assets, not circulating currencies.
///         - **Sentinels** (XXX/XTS): "no currency" marker and the
///           reserved test code. Neither is a currency.
///         - **Funds codes** (BOV, CHE, CHW, CLF, COU, MXV, USN, UYI,
///           UYW): indexing units, internal accounting devices, and
///           forex conventions. Most exist to denominate
///           inflation-indexed obligations or settlement timing; a
///           stablecoin pegged to "CLF" or "USN" is not coherent
///           because those aren't things one can hold or settle in.
///
///         **Trust model recap.** The allowlist gates the *format and
///         membership* of the identifier, not the truthfulness of the
///         issuer's claim. A factory call with `currency = "USD"` and
///         no backing reserves still succeeds at this layer. Any
///         protocol that consumes `currency()` to make an authorization
///         or routing decision is responsible for its own admission
///         logic on top.
///
///         **Implementation note.** Allowlist membership is tested by
///         comparing `keccak256(bytes(code))` against the hash of each
///         allowlist entry. Hashes of string literals are constant
///         expressions under the optimizer, so the per-call cost is
///         one keccak256 on the 3-byte input plus a chain of 32-byte
///         equalities. The alternative — direct `bytes3` comparison
///         via casts — trips forge-lint's `unsafe-typecast` rule on
///         every literal and requires ~150 inline suppressions; this
///         form keeps the lint clean without sacrificing readability.
///
///         **Updating the lists.** Adding a new ISO 4217 active code
///         (rare; registrations happen on the order of once per year)
///         is a contract change here or in the Rust precompile that
///         mirrors it. Both lists are organized alphabetically by
///         leading letter (allowlist) or by exclusion category
///         (blocklist) for ease of audit and diff.
library ISO4217 {
    /// @notice Thrown by `excludedAt` when `idx` exceeds `excludedCount`.
    error IndexOutOfBounds(uint256 idx);

    /// @notice Returns true iff `code` is exactly three ASCII bytes
    ///         long and matches an active ISO 4217 circulating-fiat
    ///         alphabetic code. See the library-level natspec for the
    ///         scope and the rationale behind every exclusion.
    function isValidFiatCode(string memory code) internal pure returns (bool) {
        bytes memory b = bytes(code);
        if (b.length != 3) return false;
        bytes32 h = keccak256(b);

        // A: Arabian-region, Caucasus, Latin-America, Pacific
        if (
            h == keccak256("AED") || h == keccak256("AFN") || h == keccak256("ALL") || h == keccak256("AMD")
                || h == keccak256("ANG") || h == keccak256("AOA") || h == keccak256("ARS") || h == keccak256("AUD")
                || h == keccak256("AWG") || h == keccak256("AZN")
        ) return true;
        // B
        if (
            h == keccak256("BAM") || h == keccak256("BBD") || h == keccak256("BDT") || h == keccak256("BGN")
                || h == keccak256("BHD") || h == keccak256("BIF") || h == keccak256("BMD") || h == keccak256("BND")
                || h == keccak256("BOB") || h == keccak256("BRL") || h == keccak256("BSD") || h == keccak256("BTN")
                || h == keccak256("BWP") || h == keccak256("BYN") || h == keccak256("BZD")
        ) return true;
        // C
        if (
            h == keccak256("CAD") || h == keccak256("CDF") || h == keccak256("CHF") || h == keccak256("CNY")
                || h == keccak256("COP") || h == keccak256("CRC") || h == keccak256("CUP") || h == keccak256("CVE")
                || h == keccak256("CZK")
        ) return true;
        // D, E
        if (
            h == keccak256("DJF") || h == keccak256("DKK") || h == keccak256("DOP") || h == keccak256("DZD")
                || h == keccak256("EGP") || h == keccak256("ERN") || h == keccak256("ETB") || h == keccak256("EUR")
        ) return true;
        // F, G
        if (
            h == keccak256("FJD") || h == keccak256("FKP") || h == keccak256("GBP") || h == keccak256("GEL")
                || h == keccak256("GHS") || h == keccak256("GIP") || h == keccak256("GMD") || h == keccak256("GNF")
                || h == keccak256("GTQ") || h == keccak256("GYD")
        ) return true;
        // H, I
        if (
            h == keccak256("HKD") || h == keccak256("HNL") || h == keccak256("HTG") || h == keccak256("HUF")
                || h == keccak256("IDR") || h == keccak256("ILS") || h == keccak256("INR") || h == keccak256("IQD")
                || h == keccak256("IRR") || h == keccak256("ISK")
        ) return true;
        // J, K
        if (
            h == keccak256("JMD") || h == keccak256("JOD") || h == keccak256("JPY") || h == keccak256("KES")
                || h == keccak256("KGS") || h == keccak256("KHR") || h == keccak256("KMF") || h == keccak256("KPW")
                || h == keccak256("KRW") || h == keccak256("KWD") || h == keccak256("KYD") || h == keccak256("KZT")
        ) return true;
        // L
        if (
            h == keccak256("LAK") || h == keccak256("LBP") || h == keccak256("LKR") || h == keccak256("LRD")
                || h == keccak256("LSL") || h == keccak256("LYD")
        ) return true;
        // M
        if (
            h == keccak256("MAD") || h == keccak256("MDL") || h == keccak256("MGA") || h == keccak256("MKD")
                || h == keccak256("MMK") || h == keccak256("MNT") || h == keccak256("MOP") || h == keccak256("MRU")
                || h == keccak256("MUR") || h == keccak256("MVR") || h == keccak256("MWK") || h == keccak256("MXN")
                || h == keccak256("MYR") || h == keccak256("MZN")
        ) return true;
        // N, O
        if (
            h == keccak256("NAD") || h == keccak256("NGN") || h == keccak256("NIO") || h == keccak256("NOK")
                || h == keccak256("NPR") || h == keccak256("NZD") || h == keccak256("OMR")
        ) return true;
        // P, Q
        if (
            h == keccak256("PAB") || h == keccak256("PEN") || h == keccak256("PGK") || h == keccak256("PHP")
                || h == keccak256("PKR") || h == keccak256("PLN") || h == keccak256("PYG") || h == keccak256("QAR")
        ) return true;
        // R
        if (h == keccak256("RON") || h == keccak256("RSD") || h == keccak256("RUB") || h == keccak256("RWF")) {
            return true;
        }
        // S
        if (
            h == keccak256("SAR") || h == keccak256("SBD") || h == keccak256("SCR") || h == keccak256("SDG")
                || h == keccak256("SEK") || h == keccak256("SGD") || h == keccak256("SHP") || h == keccak256("SLE")
                || h == keccak256("SOS") || h == keccak256("SRD") || h == keccak256("SSP") || h == keccak256("STN")
                || h == keccak256("SVC") || h == keccak256("SYP") || h == keccak256("SZL")
        ) return true;
        // T
        if (
            h == keccak256("THB") || h == keccak256("TJS") || h == keccak256("TMT") || h == keccak256("TND")
                || h == keccak256("TOP") || h == keccak256("TRY") || h == keccak256("TTD") || h == keccak256("TWD")
                || h == keccak256("TZS")
        ) return true;
        // U
        if (
            h == keccak256("UAH") || h == keccak256("UGX") || h == keccak256("USD") || h == keccak256("UYU")
                || h == keccak256("UZS")
        ) return true;
        // V, W
        if (
            h == keccak256("VED") || h == keccak256("VES") || h == keccak256("VND") || h == keccak256("VUV")
                || h == keccak256("WST")
        ) return true;
        // X (multi-country circulating fiat — see library natspec for
        // why these four codes are deliberately accepted despite the
        // X-prefix being commonly associated with non-currency entries)
        if (
            h == keccak256("XAF") || h == keccak256("XCD") || h == keccak256("XOF") || h == keccak256("XPF")
        ) return true;
        // Y, Z
        if (h == keccak256("YER") || h == keccak256("ZAR") || h == keccak256("ZMW") || h == keccak256("ZWG")) {
            return true;
        }

        return false;
    }

    /// @notice The number of ISO 4217 alphabetic codes that are on
    ///         the standard but deliberately excluded from
    ///         `isValidFiatCode`. Pair with `excludedAt` to enumerate.
    ///
    /// @dev    The blocklist exists to document — rather than silently
    ///         drop — every ISO 4217 entry that was considered for
    ///         inclusion and rejected, so the rejected set is readable
    ///         as data (with per-entry rationale in `excludedAt`'s
    ///         body) and so tests can fuzz over the full blocklist to
    ///         prove the validator's exclusions match the documented
    ///         design. Deprecated / withdrawn codes (CUC, HRK, VEF,
    ///         ZWL, etc.) are NOT in the blocklist because they're no
    ///         longer on the ISO 4217 active list at all; the
    ///         universal-rejection guarantee of `isValidFiatCode`
    ///         covers them by default.
    function excludedCount() internal pure returns (uint256) {
        return 22;
    }

    /// @notice Returns the ISO 4217 alphabetic code at index `idx` in
    ///         the blocklist. See `excludedCount` for the rationale and
    ///         the per-category inline comments below for why each
    ///         entry is excluded.
    ///
    /// @dev    Index order is stable across categories — adding new
    ///         entries appends to the end. Tests fuzzing the blocklist
    ///         should drive `idx` by `seed % excludedCount()` so they
    ///         pick up new entries automatically as the list grows.
    function excludedAt(uint256 idx) internal pure returns (string memory) {
        // Precious metals (commodities, not means of payment).
        // Commodity-backed tokens belong on the B-20 Security variant.
        if (idx == 0) return "XAU"; // Gold
        if (idx == 1) return "XAG"; // Silver
        if (idx == 2) return "XPT"; // Platinum
        if (idx == 3) return "XPD"; // Palladium

        // European composite units (defunct supranational accounting
        // units retained on ISO 4217 for historical reconciliation).
        if (idx == 4) return "XBA"; // European Composite Unit (EURCO)
        if (idx == 5) return "XBB"; // European Monetary Unit (E.M.U.-6)
        if (idx == 6) return "XBC"; // European Unit of Account 9 (E.U.A.-9)
        if (idx == 7) return "XBD"; // European Unit of Account 17 (E.U.A.-17)

        // Other supranational synthetic units (reserve assets and
        // composite indices, not circulating currencies).
        if (idx == 8) return "XDR"; // IMF Special Drawing Rights
        if (idx == 9) return "XSU"; // Sucre (ALBA regional unit)
        if (idx == 10) return "XUA"; // ADB Unit of Account

        // Sentinels (reserved by ISO 4217 for "no currency" and "test"
        // — neither denotes an actual currency).
        if (idx == 11) return "XXX"; // No-currency marker
        if (idx == 12) return "XTS"; // Test code

        // Funds codes (indexing units, internal accounting devices,
        // and forex conventions). These exist to denominate
        // inflation-indexed obligations or settlement timing; they
        // are not things one can hold or settle in, so a stablecoin
        // pegged to them is not coherent.
        if (idx == 13) return "BOV"; // Bolivian Mvdol (indexing unit)
        if (idx == 14) return "CHE"; // WIR Euro (Swiss complementary, WIR Bank)
        if (idx == 15) return "CHW"; // WIR Franc (Swiss complementary, WIR Bank)
        if (idx == 16) return "CLF"; // Chilean Unidad de Fomento (inflation-indexed)
        if (idx == 17) return "COU"; // Colombian Unidad de Valor Real (inflation-indexed)
        if (idx == 18) return "MXV"; // Mexican Unidad de Inversión (inflation-indexed)
        if (idx == 19) return "USN"; // US Dollar Next Day (forex settlement convention)
        if (idx == 20) return "UYI"; // Uruguayan UI (inflation-indexed)
        if (idx == 21) return "UYW"; // Uruguayan Unidad Previsional (pension indexing)

        revert IndexOutOfBounds(idx);
    }
}
