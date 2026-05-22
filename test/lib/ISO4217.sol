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

    // ============================================================
    //   Allowlist (ISO 4217 active circulating-fiat alphabetic codes)
    // ============================================================
    // Declared as `bytes3` constants so the lookup is a direct
    // 32-byte equality (no keccak per comparison) and the canonical
    // list is visible as data at the top of the file. Organized
    // alphabetically for diff / audit against the ISO 4217 register.

    bytes3 private constant AED = "AED";
    bytes3 private constant AFN = "AFN";
    bytes3 private constant ALL = "ALL";
    bytes3 private constant AMD = "AMD";
    bytes3 private constant ANG = "ANG"; // ISO-withdrawn 2025-03-31 (replaced by XCG); kept for backwards compatibility
    bytes3 private constant AOA = "AOA";
    bytes3 private constant ARS = "ARS";
    bytes3 private constant AUD = "AUD";
    bytes3 private constant AWG = "AWG";
    bytes3 private constant AZN = "AZN";

    bytes3 private constant BAM = "BAM";
    bytes3 private constant BBD = "BBD";
    bytes3 private constant BDT = "BDT";
    bytes3 private constant BGN = "BGN"; // ISO-withdrawn 2026-01-01 (Amendment 180, Bulgaria → EUR); kept for backwards compatibility
    bytes3 private constant BHD = "BHD";
    bytes3 private constant BIF = "BIF";
    bytes3 private constant BMD = "BMD";
    bytes3 private constant BND = "BND";
    bytes3 private constant BOB = "BOB";
    bytes3 private constant BRL = "BRL";
    bytes3 private constant BSD = "BSD";
    bytes3 private constant BTN = "BTN";
    bytes3 private constant BWP = "BWP";
    bytes3 private constant BYN = "BYN";
    bytes3 private constant BZD = "BZD";

    bytes3 private constant CAD = "CAD";
    bytes3 private constant CDF = "CDF";
    bytes3 private constant CHF = "CHF";
    bytes3 private constant CLP = "CLP";
    bytes3 private constant CNY = "CNY";
    bytes3 private constant COP = "COP";
    bytes3 private constant CRC = "CRC";
    bytes3 private constant CUP = "CUP";
    bytes3 private constant CVE = "CVE";
    bytes3 private constant CZK = "CZK";

    bytes3 private constant DJF = "DJF";
    bytes3 private constant DKK = "DKK";
    bytes3 private constant DOP = "DOP";
    bytes3 private constant DZD = "DZD";

    bytes3 private constant EGP = "EGP";
    bytes3 private constant ERN = "ERN";
    bytes3 private constant ETB = "ETB";
    bytes3 private constant EUR = "EUR";

    bytes3 private constant FJD = "FJD";
    bytes3 private constant FKP = "FKP";

    bytes3 private constant GBP = "GBP";
    bytes3 private constant GEL = "GEL";
    bytes3 private constant GHS = "GHS";
    bytes3 private constant GIP = "GIP";
    bytes3 private constant GMD = "GMD";
    bytes3 private constant GNF = "GNF";
    bytes3 private constant GTQ = "GTQ";
    bytes3 private constant GYD = "GYD";

    bytes3 private constant HKD = "HKD";
    bytes3 private constant HNL = "HNL";
    bytes3 private constant HTG = "HTG";
    bytes3 private constant HUF = "HUF";

    bytes3 private constant IDR = "IDR";
    bytes3 private constant ILS = "ILS";
    bytes3 private constant INR = "INR";
    bytes3 private constant IQD = "IQD";
    bytes3 private constant IRR = "IRR";
    bytes3 private constant ISK = "ISK";

    bytes3 private constant JMD = "JMD";
    bytes3 private constant JOD = "JOD";
    bytes3 private constant JPY = "JPY";

    bytes3 private constant KES = "KES";
    bytes3 private constant KGS = "KGS";
    bytes3 private constant KHR = "KHR";
    bytes3 private constant KMF = "KMF";
    bytes3 private constant KPW = "KPW";
    bytes3 private constant KRW = "KRW";
    bytes3 private constant KWD = "KWD";
    bytes3 private constant KYD = "KYD";
    bytes3 private constant KZT = "KZT";

    bytes3 private constant LAK = "LAK";
    bytes3 private constant LBP = "LBP";
    bytes3 private constant LKR = "LKR";
    bytes3 private constant LRD = "LRD";
    bytes3 private constant LSL = "LSL";
    bytes3 private constant LYD = "LYD";

    bytes3 private constant MAD = "MAD";
    bytes3 private constant MDL = "MDL";
    bytes3 private constant MGA = "MGA";
    bytes3 private constant MKD = "MKD";
    bytes3 private constant MMK = "MMK";
    bytes3 private constant MNT = "MNT";
    bytes3 private constant MOP = "MOP";
    bytes3 private constant MRU = "MRU";
    bytes3 private constant MUR = "MUR";
    bytes3 private constant MVR = "MVR";
    bytes3 private constant MWK = "MWK";
    bytes3 private constant MXN = "MXN";
    bytes3 private constant MYR = "MYR";
    bytes3 private constant MZN = "MZN";

    bytes3 private constant NAD = "NAD";
    bytes3 private constant NGN = "NGN";
    bytes3 private constant NIO = "NIO";
    bytes3 private constant NOK = "NOK";
    bytes3 private constant NPR = "NPR";
    bytes3 private constant NZD = "NZD";

    bytes3 private constant OMR = "OMR";

    bytes3 private constant PAB = "PAB";
    bytes3 private constant PEN = "PEN";
    bytes3 private constant PGK = "PGK";
    bytes3 private constant PHP = "PHP";
    bytes3 private constant PKR = "PKR";
    bytes3 private constant PLN = "PLN";
    bytes3 private constant PYG = "PYG";

    bytes3 private constant QAR = "QAR";

    bytes3 private constant RON = "RON";
    bytes3 private constant RSD = "RSD";
    bytes3 private constant RUB = "RUB";
    bytes3 private constant RWF = "RWF";

    bytes3 private constant SAR = "SAR";
    bytes3 private constant SBD = "SBD";
    bytes3 private constant SCR = "SCR";
    bytes3 private constant SDG = "SDG";
    bytes3 private constant SEK = "SEK";
    bytes3 private constant SGD = "SGD";
    bytes3 private constant SHP = "SHP";
    bytes3 private constant SLE = "SLE";
    bytes3 private constant SOS = "SOS";
    bytes3 private constant SRD = "SRD";
    bytes3 private constant SSP = "SSP";
    bytes3 private constant STN = "STN";
    bytes3 private constant SVC = "SVC";
    bytes3 private constant SYP = "SYP";
    bytes3 private constant SZL = "SZL";

    bytes3 private constant THB = "THB";
    bytes3 private constant TJS = "TJS";
    bytes3 private constant TMT = "TMT";
    bytes3 private constant TND = "TND";
    bytes3 private constant TOP = "TOP";
    bytes3 private constant TRY = "TRY";
    bytes3 private constant TTD = "TTD";
    bytes3 private constant TWD = "TWD";
    bytes3 private constant TZS = "TZS";

    bytes3 private constant UAH = "UAH";
    bytes3 private constant UGX = "UGX";
    bytes3 private constant USD = "USD";
    bytes3 private constant UYU = "UYU";
    bytes3 private constant UZS = "UZS";

    bytes3 private constant VED = "VED";
    bytes3 private constant VES = "VES";
    bytes3 private constant VND = "VND";
    bytes3 private constant VUV = "VUV";

    bytes3 private constant WST = "WST";

    // Multi-country circulating fiat (BCEAO, BEAC, ECCB, IEOM, CBCS).
    bytes3 private constant XAF = "XAF";
    bytes3 private constant XCD = "XCD";
    bytes3 private constant XCG = "XCG";
    bytes3 private constant XOF = "XOF";
    bytes3 private constant XPF = "XPF";

    bytes3 private constant YER = "YER";

    bytes3 private constant ZAR = "ZAR";
    bytes3 private constant ZMW = "ZMW";
    bytes3 private constant ZWG = "ZWG";

    /// @notice Returns true iff `code` is on the active ISO 4217
    ///         circulating-fiat allowlist (exactly three ASCII bytes,
    ///         uppercase, on the curated set).
    /// @dev    O(1) per call: first-byte dispatch routes to a single
    ///         letter bucket of at most 15 entries (S is the largest;
    ///         most are <10). Worst case ≈ 16 word-equality
    ///         comparisons, vs ≈ 155 for a flat chain.
    ///
    ///         Within each bucket, entries are ordered by approximate
    ///         FX-volume / economic-size / population so common codes
    ///         short-circuit early — e.g. USD is the first comparison
    ///         in the U bucket, EUR in E, JPY in J, CHF/CNY/CAD lead C.
    ///         Mean comparison count for real-world traffic is closer
    ///         to ~2 (first-byte + first match) than to the worst case.
    ///         Letters with no allowlist entries fall through to
    ///         `return false`.
    function isValidFiatCode(string memory code) internal pure returns (bool) {
        bytes memory b = bytes(code);
        if (b.length != 3) return false;
        bytes3 c;
        // Left-justified 3-byte load; trailing 29 bytes are zero per
        // Solidity's memory-zeroing guarantee between allocations.
        // forge-lint: disable-next-line(asm-keccak256)
        assembly {
            c := mload(add(b, 32))
        }
        bytes1 first = bytes1(c);

        // U: USD dominates global stablecoin volume — first match.
        if (first == "U") return c == USD || c == UAH || c == UGX || c == UYU || c == UZS;
        // E: EUR is top-2 in FX turnover.
        if (first == "E") return c == EUR || c == EGP || c == ETB || c == ERN;
        // J: JPY is G10.
        if (first == "J") return c == JPY || c == JMD || c == JOD;
        // G: GBP is G10.
        if (first == "G") {
            return c == GBP || c == GHS || c == GEL || c == GTQ || c == GIP || c == GMD || c == GNF
                || c == GYD;
        }
        // C: three G10/major currencies (CHF, CNY, CAD) lead, then CZK.
        if (first == "C") {
            return c == CHF || c == CNY || c == CAD || c == CZK || c == COP || c == CLP || c == CRC
                || c == CUP || c == CVE || c == CDF;
        }
        // A: AUD is G10; AED is a high-volume oil-linked unit.
        if (first == "A") {
            return c == AUD || c == AED || c == ARS || c == AMD || c == ANG || c == AOA || c == AFN
                || c == ALL || c == AWG || c == AZN;
        }
        // N: NOK and NZD are both G10; NGN is the largest African economy.
        if (first == "N") return c == NOK || c == NZD || c == NGN || c == NPR || c == NIO || c == NAD;
        // S: SEK (G10), SGD (MAS-anchored), SAR (oil), then long tail.
        if (first == "S") {
            return c == SEK || c == SGD || c == SAR || c == SHP || c == SCR || c == SBD || c == SDG
                || c == SLE || c == SOS || c == SRD || c == SSP || c == STN || c == SVC || c == SYP
                || c == SZL;
        }
        // I: INR / IDR / ILS dominate the bucket.
        if (first == "I") return c == INR || c == IDR || c == ILS || c == ISK || c == IQD || c == IRR;
        // M: MXN (top-15 FX), MYR, MAD.
        if (first == "M") {
            return c == MXN || c == MYR || c == MAD || c == MNT || c == MMK || c == MUR || c == MOP
                || c == MVR || c == MWK || c == MGA || c == MDL || c == MZN || c == MKD || c == MRU;
        }
        // T: TRY (notable for stablecoin demand under inflation), THB, TWD.
        if (first == "T") {
            return c == TRY || c == THB || c == TWD || c == TZS || c == TND || c == TOP || c == TTD
                || c == TJS || c == TMT;
        }
        // P: PLN (top-20 FX), PHP, PKR.
        if (first == "P") {
            return c == PLN || c == PHP || c == PKR || c == PEN || c == PGK || c == PYG || c == PAB;
        }
        // K: KRW dominates the bucket.
        if (first == "K") {
            return c == KRW || c == KZT || c == KES || c == KWD || c == KGS || c == KHR || c == KMF
                || c == KPW || c == KYD;
        }
        // B: BRL is the major; rest are long-tail.
        if (first == "B") {
            return c == BRL || c == BHD || c == BDT || c == BGN || c == BAM || c == BBD || c == BIF
                || c == BMD || c == BND || c == BOB || c == BSD || c == BTN || c == BWP || c == BYN
                || c == BZD;
        }
        // H: HKD is a major financial-center currency.
        if (first == "H") return c == HKD || c == HUF || c == HNL || c == HTG;
        // R: RUB is top-20 FX (though sanctioned).
        if (first == "R") return c == RUB || c == RON || c == RSD || c == RWF;
        // D: DKK is top-25 FX.
        if (first == "D") return c == DKK || c == DOP || c == DZD || c == DJF;
        // X: multi-country circulating fiat; XOF covers the largest population.
        if (first == "X") return c == XOF || c == XAF || c == XCD || c == XCG || c == XPF;
        // Z: ZAR is top-25 FX.
        if (first == "Z") return c == ZAR || c == ZMW || c == ZWG;
        // V: VND is the largest by economy/population in the bucket.
        if (first == "V") return c == VND || c == VES || c == VED || c == VUV;
        // L: LKR / LBP are roughly the most active.
        if (first == "L") return c == LKR || c == LBP || c == LAK || c == LRD || c == LSL || c == LYD;
        // Letters with one entry (O/Q/W/Y) and tiny multi-entry buckets (F).
        if (first == "F") return c == FJD || c == FKP;
        if (first == "O") return c == OMR;
        if (first == "Q") return c == QAR;
        if (first == "W") return c == WST;
        if (first == "Y") return c == YER;

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
