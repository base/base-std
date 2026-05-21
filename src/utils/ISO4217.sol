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
    bytes3 private constant ANG = "ANG";
    bytes3 private constant AOA = "AOA";
    bytes3 private constant ARS = "ARS";
    bytes3 private constant AUD = "AUD";
    bytes3 private constant AWG = "AWG";
    bytes3 private constant AZN = "AZN";

    bytes3 private constant BAM = "BAM";
    bytes3 private constant BBD = "BBD";
    bytes3 private constant BDT = "BDT";
    bytes3 private constant BGN = "BGN";
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

    // Multi-country circulating fiat (BCEAO, BEAC, ECCB, IEOM).
    bytes3 private constant XAF = "XAF";
    bytes3 private constant XCD = "XCD";
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
    ///         comparisons, vs ≈ 155 for a flat chain. Letters with
    ///         no allowlist entries fall through to `return false`.
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

        if (first == "A") {
            return c == AED || c == AFN || c == ALL || c == AMD || c == ANG || c == AOA || c == ARS
                || c == AUD || c == AWG || c == AZN;
        }
        if (first == "B") {
            return c == BAM || c == BBD || c == BDT || c == BGN || c == BHD || c == BIF || c == BMD
                || c == BND || c == BOB || c == BRL || c == BSD || c == BTN || c == BWP || c == BYN
                || c == BZD;
        }
        if (first == "C") {
            return c == CAD || c == CDF || c == CHF || c == CNY || c == COP || c == CRC || c == CUP
                || c == CVE || c == CZK;
        }
        if (first == "D") return c == DJF || c == DKK || c == DOP || c == DZD;
        if (first == "E") return c == EGP || c == ERN || c == ETB || c == EUR;
        if (first == "F") return c == FJD || c == FKP;
        if (first == "G") {
            return c == GBP || c == GEL || c == GHS || c == GIP || c == GMD || c == GNF || c == GTQ
                || c == GYD;
        }
        if (first == "H") return c == HKD || c == HNL || c == HTG || c == HUF;
        if (first == "I") return c == IDR || c == ILS || c == INR || c == IQD || c == IRR || c == ISK;
        if (first == "J") return c == JMD || c == JOD || c == JPY;
        if (first == "K") {
            return c == KES || c == KGS || c == KHR || c == KMF || c == KPW || c == KRW || c == KWD
                || c == KYD || c == KZT;
        }
        if (first == "L") return c == LAK || c == LBP || c == LKR || c == LRD || c == LSL || c == LYD;
        if (first == "M") {
            return c == MAD || c == MDL || c == MGA || c == MKD || c == MMK || c == MNT || c == MOP
                || c == MRU || c == MUR || c == MVR || c == MWK || c == MXN || c == MYR || c == MZN;
        }
        if (first == "N") return c == NAD || c == NGN || c == NIO || c == NOK || c == NPR || c == NZD;
        if (first == "O") return c == OMR;
        if (first == "P") {
            return c == PAB || c == PEN || c == PGK || c == PHP || c == PKR || c == PLN || c == PYG;
        }
        if (first == "Q") return c == QAR;
        if (first == "R") return c == RON || c == RSD || c == RUB || c == RWF;
        if (first == "S") {
            return c == SAR || c == SBD || c == SCR || c == SDG || c == SEK || c == SGD || c == SHP
                || c == SLE || c == SOS || c == SRD || c == SSP || c == STN || c == SVC || c == SYP
                || c == SZL;
        }
        if (first == "T") {
            return c == THB || c == TJS || c == TMT || c == TND || c == TOP || c == TRY || c == TTD
                || c == TWD || c == TZS;
        }
        if (first == "U") return c == UAH || c == UGX || c == USD || c == UYU || c == UZS;
        if (first == "V") return c == VED || c == VES || c == VND || c == VUV;
        if (first == "W") return c == WST;
        if (first == "X") return c == XAF || c == XCD || c == XOF || c == XPF;
        if (first == "Y") return c == YER;
        if (first == "Z") return c == ZAR || c == ZMW || c == ZWG;

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
