// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockB20Storage
/// @notice Slot-layout library for the `MockB20` reference implementation.
///
///         Every piece of mutable token state lives in this struct at a single
///         ERC-7201-namespaced location, so the Rust precompile implementation
///         has an unambiguous, audit-grep-able source of truth for which slot
///         holds what.
///
/// @dev    The token contract is a precompile in production: every B-20 token
///         lives at a factory-derived address with its own storage. This mock
///         is etched at that same address via `vm.etch` so the storage
///         layout the Rust impl computes maps slot-for-slot to what this
///         library defines.
///
///         **Why ERC-7201 over a flat unstructured-storage list?** Two reasons:
///         1. The struct field ORDER is the slot layout. There is no separate
///            "list of slot constants" that can drift out of sync with the
///            fields they describe. The Rust impl reads this struct top-to-
///            bottom and replicates the same ordering.
///         2. Solidity's type system handles all the dynamic-storage encoding
///            (string length-vs-data, mapping key hashing, etc.) for us, so
///            we don't reimplement those Rust-side either — we just match
///            Solidity's documented storage layout.
///
///         **Namespace:** `base.b20`. The ERC-7201 location is
///         `keccak256(abi.encode(uint256(keccak256("base.b20")) - 1)) & ~bytes32(uint256(0xff))`.
///
///         Variant-specific state lives in its own library (e.g.
///         `MockB20StablecoinStorage` for the `currency` field) at a
///         disjoint namespace, so variants compose without slot conflict.
///
///         Identity state (`name`, `symbol`) is kept in this struct rather
///         than encoded into the address because mutability is required
///         (`setName` / `setSymbol` on the IB20 surface). `decimals` is
///         variant-fixed (`18` for default, `6` for stablecoin/security)
///         and read from code, not storage.
library MockB20Storage {
    /// @custom:storage-location erc7201:base.b20
    struct Layout {
        // ---------- Identity (mutable via admin) ----------
        string name;
        string symbol;
        string contractURI;
        // ---------- ERC-20 ----------
        uint256 totalSupply;
        mapping(address account => uint256 balance) balances;
        mapping(address owner => mapping(address spender => uint256 allowance)) allowances;
        // ---------- Roles (OZ AccessControl-style) ----------
        mapping(bytes32 role => mapping(address account => bool isMember)) roles;
        mapping(bytes32 role => bytes32 adminRole) roleAdmins;
        // Tracks DEFAULT_ADMIN_ROLE holder count so renounceRole can enforce
        // LastAdminCannotRenounce in O(1). Bumped on grant, decremented on
        // revoke / renounce.
        uint248 adminCount;
        // False from etch until the factory sets it true at the end of
        // createToken. Packed with adminCount in the same slot to avoid
        // dedicating a full slot to a single flag.
        bool initialized;
        // ---------- Policy slots (PACKED, per-operation) ----------
        // Hot-path policy IDs live in per-operation packed slots so each
        // op reads exactly one slot, AND so adding granularity to one op
        // (e.g. future MINT_AUTHORIZER) doesn't push other ops' IDs into
        // a second SLOAD. Each slot holds four uint64s; the 64-bit width
        // matches `uint64 policyId` everywhere else in the system, and
        // four IDs fit exactly into the 256-bit slot.
        //
        // Transfer-side policies (read by `_transfer`, `transferFrom*`,
        // and the seize check in `burnBlocked`).
        // Packed as four uint64 lanes from least-significant to most-significant:
        //   word0 (bytes  0.. 7, bits   0.. 63): transferSenderPolicyId
        //   word1 (bytes  8..15, bits  64..127): transferReceiverPolicyId
        //   word2 (bytes 16..23, bits 128..191): transferExecutorPolicyId
        //   word3 (bytes 24..31, bits 192..255): reserved
        // Note: bit ranges are shown low..high to avoid [end:start] ambiguity.
        uint256 transferPolicyIds;
        // Mint-side policies (read by `_mint`). Only `MINT_RECEIVER_POLICY` is
        // defined today; the remaining three uint64 slots are reserved
        // for future granular mint-side policy types (e.g.
        // MINT_AUTHORIZER) so adding one doesn't force a second SLOAD.
        // Layout uses the same uint64 lane convention:
        //   word0 (bytes  0.. 7, bits   0.. 63): mintReceiverPolicyId
        //   word1 (bytes  8..15, bits  64..127): reserved
        //   word2 (bytes 16..23, bits 128..191): reserved
        //   word3 (bytes 24..31, bits 192..255): reserved
        uint256 mintPolicyIds;
        // There is no generic fallback mapping for "other" policy
        // types. Each supported `policyType` lives in a fixed slot on
        // this struct (or, for variant-specific operations, in the
        // variant's own namespaced storage library — e.g. a future
        // `MockB20SecurityStorage` adds `redeemPolicyIds` at namespace
        // `base.b20.security`, mirroring how `MockB20StablecoinStorage`
        // adds `currency` at `base.b20.stablecoin`). `updatePolicy` on
        // an unsupported `policyType` reverts `UnsupportedPolicyType`.
        // ---------- Pause ----------
        // Bitmask: bit i set means PausableFeature(i) is paused. Translated
        // to/from the PausableFeature[] enum array at the IB20 surface
        // boundary.
        uint256 pausedVectors;
        // ---------- Supply cap ----------
        uint256 supplyCap;
        // ---------- Permit (EIP-2612) ----------
        mapping(address owner => uint256 nonce) nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("base.b20")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0xc78b71fee795ddd74aff64ea9b2474194c938c3196430e10bb5f01ed48434000;

    // ============================================================
    //                     SLOT OFFSETS WITHIN LAYOUT
    // ============================================================
    // Solidity allocates struct fields sequentially starting at the
    // struct's base slot. These constants name each field's offset
    // from `STORAGE_LOCATION` so the factory (and the Rust impl) can
    // write the token's initial state directly via slot arithmetic
    // without round-tripping through a Solidity function call on the
    // token. They MUST stay in sync with the field order of `Layout`
    // above; the variant-storage test asserts this by reading via the
    // struct AND via the offset and comparing.
    //
    // Mappings consume one declared slot here (their VALUES hash to
    // unrelated locations), so each mapping below contributes a single
    // offset that the factory uses as the mapping's base slot when
    // deriving member slots via `keccak256(abi.encode(key, baseSlot))`.

    uint256 internal constant NAME_OFFSET = 0;
    uint256 internal constant SYMBOL_OFFSET = 1;
    uint256 internal constant CONTRACT_URI_OFFSET = 2;
    uint256 internal constant TOTAL_SUPPLY_OFFSET = 3;
    uint256 internal constant BALANCES_OFFSET = 4;
    uint256 internal constant ALLOWANCES_OFFSET = 5;
    uint256 internal constant ROLES_OFFSET = 6;
    uint256 internal constant ROLE_ADMINS_OFFSET = 7;
    uint256 internal constant ADMIN_COUNT_OFFSET = 8;
    uint256 internal constant INITIALIZED_OFFSET = 8;
    // `initialized` is the high byte in slot 8 (packed after uint248 adminCount).
    uint8 internal constant INITIALIZED_BYTE_OFFSET = 31;
    uint256 internal constant TRANSFER_POLICY_IDS_OFFSET = 9;
    uint256 internal constant MINT_POLICY_IDS_OFFSET = 10;
    uint256 internal constant PAUSED_VECTORS_OFFSET = 11;
    uint256 internal constant SUPPLY_CAP_OFFSET = 12;
    uint256 internal constant NONCES_OFFSET = 13;

    /// @notice Absolute slot for a top-level field of `Layout`.
    /// @dev `STORAGE_LOCATION + offset`. The struct never crosses the
    ///      256-slot boundary the ERC-7201 mask reserves.
    function slotOf(uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(STORAGE_LOCATION) + offset);
    }

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Returns the storage location derived per the ERC-7201 formula
    ///         from the namespace string. Used in tests to assert the
    ///         hardcoded `STORAGE_LOCATION` constant matches the formula.
    function derivedLocation() internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256("base.b20")) - 1)) & ~bytes32(uint256(0xff));
    }
}

/// @title MockB20SecurityStorage
/// @notice Slot-layout library for the `MockB20Security` variant's
///         variant-specific state. Disjoint namespace from
///         `MockB20Storage` so the variant composes additively
///         without touching the base token's slot layout, mirroring
///         how `MockB20StablecoinStorage` adds `currency` for the
///         stablecoin variant.
///
/// @dev    **Namespace:** `base.b20.security`. The ERC-7201 location
///         is `keccak256(abi.encode(uint256(keccak256("base.b20.security")) - 1)) & ~bytes32(uint256(0xff))`.
///
///         **Storage notes.**
///         - `sharesToTokensRatio` stores the WAD-scaled
///           share-to-tokens ratio. A stored value of `0` is
///           interpreted by the read surface (`sharesToTokensRatio()`,
///           `toShares(...)`, `sharesOf(...)`) as `WAD_PRECISION`, so a
///           freshly-etched token reports a 1:1 ratio without
///           requiring the factory to write the default value during
///           bootstrap. `updateShareRatio` writes the new ratio
///           verbatim; subsequent reads return the stored value as-is.
///         - `redeemPolicyIds` is a per-operation packed slot,
///           mirroring base's `transferPolicyIds` / `mintPolicyIds`
///           layout: only `REDEEMER_SENDER_POLICY` is defined today, with
///           three reserved lanes for future redeem-side granularity
///           (e.g. `REDEEMER_RECEIVER` if and when off-chain
///           settlement counterparties get policy gating).
///         - `usedAnnouncementIds` keys directly on the raw `string id`
///           that callers pass to `announce` / `isAnnouncementIdUsed`,
///           not on a hash, so the on-chain query mirrors the API.
///         - `identifiers` keys directly on the raw `identifierType`
///           string (e.g. `"ISIN"`); empty value means unset/removed.
library MockB20SecurityStorage {
    /// @custom:storage-location erc7201:base.b20.security
    struct Layout {
        // ---------- Share ratio ----------
        // Scaled by WAD_PRECISION (1e18). Stored value of 0 is
        // interpreted as WAD by the read surface.
        uint256 sharesToTokensRatio;
        // ---------- Announcements ----------
        // Tracks consumed announcement IDs; flips to true on first
        // `announce` for a given id, and remains true forever.
        mapping(string id => bool used) usedAnnouncementIds;
        // ---------- Security identifiers ----------
        // ISIN, CUSIP, FIGI, etc. Empty string means unset/removed.
        mapping(string identifierType => string value) identifiers;
    }

    // keccak256(abi.encode(uint256(keccak256("base.b20.security")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0x4a21e1b7f963e21baf0daffe6bab858a1e5fecef1144f3aca3c0c4534c7ac600;

    // ============================================================
    //                     SLOT OFFSETS WITHIN LAYOUT
    // ============================================================
    // Sequential allocation matches `Layout` field order top-to-
    // bottom. Mappings consume one slot each (their VALUES hash to
    // unrelated locations); the factory uses these as base slots when
    // deriving member slots via `keccak256(abi.encode(key, baseSlot))`.

    uint256 internal constant SHARES_TO_TOKENS_RATIO_OFFSET = 0;
    uint256 internal constant USED_ANNOUNCEMENT_IDS_OFFSET = 1;
    uint256 internal constant IDENTIFIERS_OFFSET = 2;

    /// @notice Absolute slot for a top-level field of `Layout`.
    function slotOf(uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(STORAGE_LOCATION) + offset);
    }

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Returns the storage location derived per the ERC-7201 formula
    ///         from the namespace string. Used in tests to assert the
    ///         hardcoded `STORAGE_LOCATION` constant matches the formula.
    function derivedLocation() internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256("base.b20.security")) - 1)) & ~bytes32(uint256(0xff));
    }
}

library MockB20RedeemStorage {
    // keccak256(abi.encode(uint256(keccak256("base.b20.redeem")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0xc95c24ab0255f9fb9fcdcd524f71c4fe0437265856b7e5e6d0801df0e6cf5100;

    uint256 internal constant MINIMUM_REDEEMABLE_OFFSET = 0;
    uint256 internal constant REDEEM_POLICY_IDS_OFFSET = 1;

    /// @notice Absolute slot for a top-level field of `Layout`.
    function slotOf(uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(STORAGE_LOCATION) + offset);
    }

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
    
    /// @custom:storage-location erc7201:base.b20.redeem
    struct Layout {
        // ---------- Redemption ----------
        // Floor on `redeem` / `redeemWithMemo`, expressed in shares.
        // Defaults to 0 (no floor); admin sets via updateMinimumRedeemable.
        uint256 minimumRedeemable;

        // ---------- Redeem-side policies (PACKED) ----------
        // Layout:
        //   [63:0]    redeemerSenderPolicyId
        //   [127:64]  reserved
        //   [191:128] reserved
        //   [255:192] reserved
        uint256 redeemPolicyIds;
    }

    /// @notice Returns the storage location derived per the ERC-7201 formula
    ///         from the namespace string. Used in tests to assert the
    ///         hardcoded `STORAGE_LOCATION` constant matches the formula.
    function derivedLocation() internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256("base.b20.redeem")) - 1)) & ~bytes32(uint256(0xff));
    }
}

/// @title MockB20StablecoinStorage
/// @notice Slot-layout library for the `MockB20Stablecoin` variant's
///         variant-specific state. Disjoint namespace from `MockB20Storage`
///         so the variant composes additively without touching the base
///         token's slot layout.
/// @dev    **Namespace:** `base.b20.stablecoin`. Location:
///         `keccak256(abi.encode(uint256(keccak256("base.b20.stablecoin")) - 1)) & ~bytes32(uint256(0xff))`.
library MockB20StablecoinStorage {
    /// @custom:storage-location erc7201:base.b20.stablecoin
    struct Layout {
        // Immutable post-creation. Set during factory bootstrap; no
        // mutator function. Stored at the type's natural Solidity slot
        // within this struct.
        string currency;
    }

    // keccak256(abi.encode(uint256(keccak256("base.b20.stablecoin")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0x35827975a06ca0e9367ea3129b19441d45d0ca58e30b7693f09e73d0943d6200;

    /// @notice Offset of `currency` within `Layout`. Always 0 (single-field struct).
    uint256 internal constant CURRENCY_OFFSET = 0;

    /// @notice Absolute slot for a top-level field of `Layout`.
    function slotOf(uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(STORAGE_LOCATION) + offset);
    }

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Returns the storage location derived per the ERC-7201 formula
    ///         from the namespace string. Used in tests to assert the
    ///         hardcoded `STORAGE_LOCATION` constant matches the formula.
    function derivedLocation() internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256("base.b20.stablecoin")) - 1)) & ~bytes32(uint256(0xff));
    }
}
