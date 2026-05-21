// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  ISO4217
/// @notice Helpers anchored in the ISO 4217 currency-code standard.
///         Exposes two primitives:
///         - `isValidFiatCode` — allowlist of active ISO 4217 alphabetic
///           codes for circulating national fiat currencies.
///         - `excludedCount` / `excludedAt` — enumerable record of ISO
///           4217 codes that are on the standard but deliberately
///           excluded, with per-entry rationale inline in `excludedAt`.
/// @dev    See `docs/b20/stablecoin/currency-validation.md` for scope, exclusion categories,
///         and the regulatory framing behind the narrow fiat scope.
///         Any future Rust precompile implementation must mirror both
///         lists exactly.
library ISO4217 {
    /// @notice Thrown by `excludedAt` when `idx` exceeds `excludedCount`.
    error IndexOutOfBounds(uint256 idx);

    /// @notice Returns true iff `code` is on the active ISO 4217
    ///         circulating-fiat allowlist (exactly three ASCII bytes,
    ///         uppercase, on the curated set).
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
        // X (multi-country circulating fiat: BCEAO, BEAC, ECCB, IEOM)
        if (
            h == keccak256("XAF") || h == keccak256("XCD") || h == keccak256("XOF") || h == keccak256("XPF")
        ) return true;
        // Y, Z
        if (h == keccak256("YER") || h == keccak256("ZAR") || h == keccak256("ZMW") || h == keccak256("ZWG")) {
            return true;
        }

        return false;
    }

    /// @notice Number of ISO 4217 codes deliberately excluded from
    ///         `isValidFiatCode`. Pair with `excludedAt` to enumerate.
    ///         Excludes only currently-active ISO 4217 entries; deprecated
    ///         codes (CUC, HRK, VEF, ZWL, etc.) are caught by absence
    ///         from the allowlist instead.
    function excludedCount() internal pure returns (uint256) {
        return 22;
    }

    /// @notice Returns the excluded code at index `idx`. Per-entry
    ///         rationale is inline in this function's body, grouped by
    ///         exclusion category.
    /// @dev    Index order is stable; new entries append. Fuzz tests
    ///         drive `idx` via `seed % excludedCount()` to pick up new
    ///         entries automatically.
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
