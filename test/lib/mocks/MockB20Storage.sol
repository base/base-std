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
///         (`updateName` / `updateSymbol` on the IB20 surface). `decimals` is
///         variant-fixed (`18` for default, `6` for stablecoin/asset)
///         and read from code, not storage.
library MockB20Storage {
    // ============================================================
    //                     PACKED POLICY STRUCTS
    // ============================================================
    // Solidity packs struct fields LSB-first into a single 256-bit slot
    // (all fields fit because each is `uint64` and there are at most
    // four of them per struct). The struct definition IS the binary
    // layout spec — the Rust impl mirrors the field order with `u64`s
    // of the same names. Reserved bits are implicit: any uint64 lane
    // not declared as a field is simply uninitialized (zero) and the
    // struct cannot accidentally write to it.

    /// @notice Transfer-side policy IDs (read by `_transfer`,
    ///         `transferFrom*`, and the seize check in `burnBlocked`).
    /// @dev    Bit layout (Solidity LSB-first):
    ///           bits   0.. 63 : sender
    ///           bits  64..127 : receiver
    ///           bits 128..191 : executor
    ///           bits 192..255 : reserved (implicit, no field declared)
    struct TransferPolicyIds {
        uint64 sender;
        uint64 receiver;
        uint64 executor;
    }

    /// @notice Mint-side policy IDs (read by `_mint`). Only the
    ///         receiver policy is defined today; future granular
    ///         mint-side policy types get added as additional `uint64`
    ///         fields here so adding one doesn't force a second SLOAD.
    /// @dev    Bit layout:
    ///           bits   0.. 63 : receiver
    ///           bits  64..255 : reserved (implicit)
    struct MintPolicyIds {
        uint64 receiver;
    }

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
        // revoke / renounce. Lives alone in its own slot — packing it with
        // `initialized` is no longer required since `initialized` was moved
        // out to its own slot at the end of the layout.
        uint256 adminCount;
        // ---------- Policy slots (PACKED, per-operation) ----------
        // Hot-path policy IDs live in per-operation packed slots so each
        // op reads exactly one slot, AND so adding granularity to one op
        // (e.g. future MINT_AUTHORIZER) doesn't push other ops' IDs into
        // a second SLOAD. Each slot holds four uint64s; the 64-bit width
        // matches `uint64 policyId` everywhere else in the system, and
        // four IDs fit exactly into the 256-bit slot.
        //
        // **Layout via Solidity packed structs.** Each per-op packed slot
        // is declared as a struct of `uint64` fields. Solidity packs
        // struct fields LSB-first into the slot, which is the exact
        // convention the Rust precompile impl must reproduce — so the
        // struct field DECLARATION ORDER is the binary layout spec, with
        // no comment-vs-code drift surface. Bit-identical to the prior
        // hand-rolled `uint256` layout; consumer code uses named field
        // access (`$.transferPolicyIds.sender = id;`) instead of inline
        // shifts and mask operations.
        //
        // Transfer-side policies (read by `_transfer`, `transferFrom*`,
        // and the seize check in `burnBlocked`).
        TransferPolicyIds transferPolicyIds;
        // Mint-side policies (read by `_mint`). Only `MINT_RECEIVER_POLICY`
        // is defined today; future granular mint-side policy types (e.g.
        // `MINT_AUTHORIZER`) get added as additional `uint64` fields on
        // `MintPolicyIds` so adding one doesn't force a second SLOAD.
        MintPolicyIds mintPolicyIds;
        // There is no generic fallback mapping for "other" policy
        // types. Each supported `policyType` lives in a fixed slot on
        // this struct (or, for variant-specific operations, in the
        // variant's own namespaced storage library — mirroring how
        // `MockB20StablecoinStorage` adds `currency` at
        // `base.b20.stablecoin`). `updatePolicy` on an unsupported
        // `policyType` reverts `UnsupportedPolicyType`.
        // ---------- Pause ----------
        // Bitmask: bit i set means PausableFeature(i) is paused. Translated
        // to/from the PausableFeature[] enum array at the IB20 surface
        // boundary.
        uint256 pausedVectors;
        // ---------- Supply cap ----------
        uint256 supplyCap;
        // ---------- Permit (EIP-2612) ----------
        mapping(address owner => uint256 nonce) nonces;
        // ---------- Bootstrap flag ----------
        // False from etch until the factory sets it true at the end of
        // createToken. Pinned to its own slot at the END of the layout
        // because the EVM impl uses this flag as the demarcation between
        // the privileged bootstrap window and post-init state, while the
        // Rust impl distinguishes those phases through a different
        // mechanism and does not need a storage slot for the flag at all.
        // Keeping it last lets the Rust impl's layout omit it without
        // disturbing the offset of any other field.
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
    uint256 internal constant TRANSFER_POLICY_IDS_OFFSET = 9;
    uint256 internal constant MINT_POLICY_IDS_OFFSET = 10;
    uint256 internal constant PAUSED_VECTORS_OFFSET = 11;
    uint256 internal constant SUPPLY_CAP_OFFSET = 12;
    uint256 internal constant NONCES_OFFSET = 13;
    // `initialized` sits alone in its own slot at the END of the layout;
    // see the field-level natspec above for why.
    uint256 internal constant INITIALIZED_OFFSET = 14;

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

    // ============================================================
    //                     TOP-LEVEL FIELD SLOTS
    // ============================================================
    // Convenience wrappers around `slotOf(OFFSET)` so test callers (and
    // the Rust impl validator) can read each field without remembering
    // the offset constant. Inlined by the compiler; zero runtime cost.

    // forgefmt: disable-start
    function nameSlot() internal pure returns (bytes32) { return slotOf(NAME_OFFSET); }
    function symbolSlot() internal pure returns (bytes32) { return slotOf(SYMBOL_OFFSET); }
    function contractURISlot() internal pure returns (bytes32) { return slotOf(CONTRACT_URI_OFFSET); }
    function totalSupplySlot() internal pure returns (bytes32) { return slotOf(TOTAL_SUPPLY_OFFSET); }
    function balancesBaseSlot() internal pure returns (bytes32) { return slotOf(BALANCES_OFFSET); }
    function allowancesBaseSlot() internal pure returns (bytes32) { return slotOf(ALLOWANCES_OFFSET); }
    function rolesBaseSlot() internal pure returns (bytes32) { return slotOf(ROLES_OFFSET); }
    function roleAdminsBaseSlot() internal pure returns (bytes32) { return slotOf(ROLE_ADMINS_OFFSET); }
    function adminCountSlot() internal pure returns (bytes32) { return slotOf(ADMIN_COUNT_OFFSET); }
    function transferPolicyIdsSlot() internal pure returns (bytes32) { return slotOf(TRANSFER_POLICY_IDS_OFFSET); }
    function mintPolicyIdsSlot() internal pure returns (bytes32) { return slotOf(MINT_POLICY_IDS_OFFSET); }
    function pausedVectorsSlot() internal pure returns (bytes32) { return slotOf(PAUSED_VECTORS_OFFSET); }
    function supplyCapSlot() internal pure returns (bytes32) { return slotOf(SUPPLY_CAP_OFFSET); }
    function noncesBaseSlot() internal pure returns (bytes32) { return slotOf(NONCES_OFFSET); }
    function initializedSlot() internal pure returns (bytes32) { return slotOf(INITIALIZED_OFFSET); }

        // forgefmt: disable-end

    // ============================================================
    //                     MAPPING MEMBER SLOTS
    // ============================================================
    // Solidity derives a mapping value's slot as
    //   keccak256(abi.encode(key, baseSlot))
    // where `key` is ABI-padded to 32 bytes and `baseSlot` is the slot
    // where the mapping itself is declared (the field slot, returned by
    // the `*BaseSlot()` helpers above). Nested mappings hash the outer
    // key first to obtain an inner base slot, then hash the inner key
    // against that. The Rust impl reproduces this scheme byte-for-byte.

    /// @notice Slot of `balances[account]`.
    function balanceSlot(address account) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, balancesBaseSlot()));
    }

    /// @notice Slot of `allowances[owner][spender]`.
    function allowanceSlot(address owner, address spender) internal pure returns (bytes32) {
        bytes32 ownerSlot = keccak256(abi.encode(owner, allowancesBaseSlot()));
        return keccak256(abi.encode(spender, ownerSlot));
    }

    /// @notice Slot of `roles[role][account]` (the bool membership flag).
    function roleMembershipSlot(bytes32 role, address account) internal pure returns (bytes32) {
        bytes32 roleSlot = keccak256(abi.encode(role, rolesBaseSlot()));
        return keccak256(abi.encode(account, roleSlot));
    }

    /// @notice Slot of `roleAdmins[role]`.
    function roleAdminSlot(bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(role, roleAdminsBaseSlot()));
    }

    /// @notice Slot of `nonces[owner]`.
    function nonceSlot(address owner) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, noncesBaseSlot()));
    }

    // ============================================================
    //                     PACKED-SLOT CODECS
    // ============================================================
    // Production code accesses the packed policy slots via the
    // `TransferPolicyIds` / `MintPolicyIds` structs (named fields on
    // `Layout`) — Solidity handles the bit math automatically. These
    // pure codecs operate on a raw `uint256` (what `vm.load` returns
    // for the slot) and exist for test-side use only: layout-pin tests
    // that read the raw slot bytes can use them to extract lanes
    // without re-deriving the shifts at every callsite.
    //
    // The roundtrip tests in `MockB20SlotHelpers.t.sol` verify that
    // these codecs' bit math matches Solidity's struct packing — so a
    // codec drifting away from the canonical struct layout fails CI.

    /// @notice Extracts the TRANSFER_SENDER policy id (lane 0) from the packed slot.
    function transferSenderPolicyId(uint256 packed) internal pure returns (uint64) {
        return uint64(packed);
    }

    /// @notice Extracts the TRANSFER_RECEIVER policy id (lane 1) from the packed slot.
    function transferReceiverPolicyId(uint256 packed) internal pure returns (uint64) {
        return uint64(packed >> 64);
    }

    /// @notice Extracts the TRANSFER_EXECUTOR policy id (lane 2) from the packed slot.
    function transferExecutorPolicyId(uint256 packed) internal pure returns (uint64) {
        return uint64(packed >> 128);
    }

    /// @notice Composes the transfer-side packed slot from its three lanes.
    /// @dev Lane 3 (bits 192..255) is reserved and pinned to zero.
    function packTransferPolicyIds(uint64 senderId, uint64 receiverId, uint64 executorId)
        internal
        pure
        returns (uint256)
    {
        return uint256(senderId) | (uint256(receiverId) << 64) | (uint256(executorId) << 128);
    }

    /// @notice Extracts the MINT_RECEIVER policy id (lane 0) from the packed slot.
    function mintReceiverPolicyId(uint256 packed) internal pure returns (uint64) {
        return uint64(packed);
    }

    /// @notice Composes the mint-side packed slot from its single defined lane.
    /// @dev Lanes 1..3 are reserved and pinned to zero.
    function packMintPolicyIds(uint64 receiverId) internal pure returns (uint256) {
        return uint256(receiverId);
    }
}

/// @title MockB20AssetStorage
/// @notice Slot-layout library for the `MockB20Asset` variant's
///         variant-specific state. Disjoint namespace from
///         `MockB20Storage` so the variant composes additively
///         without touching the base token's slot layout, mirroring
///         how `MockB20StablecoinStorage` adds `currency` for the
///         stablecoin variant.
///
/// @dev    **Namespace:** `base.b20.asset`. The ERC-7201 location
///         is `keccak256(abi.encode(uint256(keccak256("base.b20.asset")) - 1)) & ~bytes32(uint256(0xff))`.
///
///         **Storage notes.**
///         - `decimals` is the per-token ERC-20 decimals value, chosen
///           at creation by the factory from `B20AssetCreateParams`
///           and immutable thereafter. Validated to the range
///           `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]`
///           by the factory. Pinned to slot 0 (ahead of `multiplier`)
///           so future small variant-immutable scalars can pack into
///           this slot's remaining 31 bytes without shifting other
///           fields' offsets.
///         - `multiplier` stores the WAD-scaled multiplier applied to
///           raw balances. A stored value of `0` is interpreted by the
///           read surface (`multiplier()`, `toScaledBalance(...)`,
///           `toRawBalance(...)`, `scaledBalanceOf(...)`) as
///           `WAD_PRECISION`, so a freshly-etched token reports a 1:1
///           multiplier without requiring the factory to write the
///           default value during bootstrap. `updateMultiplier` writes
///           the new multiplier verbatim; subsequent reads return the
///           stored value as-is.
///         - `usedAnnouncementIds` keys directly on the raw `string id`
///           that callers pass to `announce` / `isAnnouncementIdUsed`,
///           not on a hash, so the on-chain query mirrors the API.
///         - `extraMetadata` (the storage field backing the public
///           `extraMetadata` / `updateExtraMetadata` surface) keys
///           directly on the raw `key` string (e.g. `"category"`);
///           empty value means unset/removed.
library MockB20AssetStorage {
    /// @custom:storage-location erc7201:base.b20.asset
    struct Layout {
        // ---------- Decimals ----------
        // Per-token ERC-20 `decimals`. Written by the factory at
        // creation from the `B20AssetCreateParams.decimals` field
        // (validated to [MIN_ASSET_DECIMALS, MAX_ASSET_DECIMALS]) and
        // never mutated afterwards. Pinned to slot 0 so future
        // small variant-immutable scalars can pack into the same
        // slot's remaining 31 bytes without disturbing offsets of
        // later fields.
        uint8 decimals;
        // ---------- Multiplier ----------
        // Scaled by WAD_PRECISION (1e18). Stored value of 0 is
        // interpreted as WAD by the read surface.
        uint256 multiplier;
        // ---------- Announcements ----------
        // Tracks consumed announcement IDs; flips to true on first
        // `announce` for a given id, and remains true forever.
        mapping(string id => bool used) usedAnnouncementIds;
        // ---------- Extra metadata ----------
        // Named string entries — a variant-agnostic key/value store
        // (e.g. `category`, `region`, `reference`). Empty string means
        // unset/removed.
        mapping(string key => string value) extraMetadata;
    }

    // keccak256(abi.encode(uint256(keccak256("base.b20.asset")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0xfdc6d4552d1286ade4d9facdbf0fb50d2ec9b89a90e104f26fd277585e374b00;

    // ============================================================
    //                     SLOT OFFSETS WITHIN LAYOUT
    // ============================================================
    // Sequential allocation matches `Layout` field order top-to-
    // bottom. Mappings consume one slot each (their VALUES hash to
    // unrelated locations); the factory uses these as base slots when
    // deriving member slots via `keccak256(abi.encode(key, baseSlot))`.

    uint256 internal constant DECIMALS_OFFSET = 0;
    uint256 internal constant MULTIPLIER_OFFSET = 1;
    uint256 internal constant USED_ANNOUNCEMENT_IDS_OFFSET = 2;
    uint256 internal constant EXTRA_METADATA_OFFSET = 3;

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
        return keccak256(abi.encode(uint256(keccak256("base.b20.asset")) - 1)) & ~bytes32(uint256(0xff));
    }

    // ============================================================
    //                     TOP-LEVEL FIELD SLOTS
    // ============================================================

    // forgefmt: disable-start
    function decimalsSlot() internal pure returns (bytes32) { return slotOf(DECIMALS_OFFSET); }
    function multiplierSlot() internal pure returns (bytes32) { return slotOf(MULTIPLIER_OFFSET); }
    function usedAnnouncementIdsBaseSlot() internal pure returns (bytes32) { return slotOf(USED_ANNOUNCEMENT_IDS_OFFSET); }
    function extraMetadataBaseSlot() internal pure returns (bytes32) { return slotOf(EXTRA_METADATA_OFFSET); }

            // forgefmt: disable-end

    // ============================================================
    //                     MAPPING MEMBER SLOTS
    // ============================================================
    // Solidity derives a string-keyed mapping value's slot as
    //   keccak256(abi.encodePacked(key, baseSlot))
    // where the string's raw bytes (unpadded) are concatenated with the
    // 32-byte base slot. The Rust impl reproduces this scheme
    // byte-for-byte.

    /// @notice Slot of `usedAnnouncementIds[id]`.
    function usedAnnouncementIdSlot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(id, usedAnnouncementIdsBaseSlot()));
    }

    /// @notice Slot of the extra-metadata entry keyed by `key`
    ///         (the value, which is itself a string and follows
    ///         Solidity's short/long encoding convention).
    function extraMetadataSlot(string memory key) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(key, extraMetadataBaseSlot()));
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

    // ============================================================
    //                     TOP-LEVEL FIELD SLOTS
    // ============================================================

    /// @notice Slot of `currency` (a `string` whose encoding follows
    ///         Solidity's short/long convention: bytes packed in-slot
    ///         with `length * 2` in the low byte when `length < 32`;
    ///         otherwise the slot stores `length * 2 + 1` and the data
    ///         starts at `keccak256(slot)`).
    // forgefmt: disable-next-item
    function currencySlot() internal pure returns (bytes32) { return slotOf(CURRENCY_OFFSET); }
}
