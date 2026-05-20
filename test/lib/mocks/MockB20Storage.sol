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
///         (`setName` / `setSymbol` on the IB20 surface). `decimals` IS
///         encoded into the address (byte `[11]`) and is retrieved via pure
///         address-decode in `MockB20.decimals()` — no storage slot.
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
        uint256 adminCount;
        // ---------- Policy slots ----------
        mapping(bytes32 policyType => uint64 policyId) policyIds;
        // ---------- Pause ----------
        // Bitmask: bit i set means PausableFeature(i) is paused. Translated
        // to/from the PausableFeature[] enum array at the IB20 surface
        // boundary.
        uint256 pausedVectors;
        // ---------- Supply cap ----------
        uint256 supplyCap;
        // ---------- Permit (EIP-2612) ----------
        mapping(address owner => uint256 nonce) nonces;
        // ---------- Bootstrap window flag ----------
        // False from etch until the factory writes `true` directly (via
        // vm.store, mirroring the Rust impl's direct slot write). While
        // false, factory-originated calls bypass all token-side authorization
        // gates (role / policy / pause checks). Token invariants (supply-cap
        // math, balance accounting) are NOT bypassed.
        bool initialized;
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
    uint256 internal constant POLICY_IDS_OFFSET = 9;
    uint256 internal constant PAUSED_VECTORS_OFFSET = 10;
    uint256 internal constant SUPPLY_CAP_OFFSET = 11;
    uint256 internal constant NONCES_OFFSET = 12;
    uint256 internal constant INITIALIZED_OFFSET = 13;

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
