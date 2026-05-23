// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockPolicyRegistryStorage
/// @notice Slot-layout library for the `MockPolicyRegistry` reference implementation.
///
///         Every piece of mutable registry state lives in this struct at a single
///         ERC-7201-namespaced location, so the Rust precompile implementation
///         has an unambiguous, audit-grep-able source of truth for which slot
///         holds what.
///
/// @dev    **Why ERC-7201 over flat unstructured storage?**
///         The struct field ORDER is the slot layout. There is no separate list
///         of slot constants that can drift out of sync with the fields they
///         describe. The Rust impl reads this struct top-to-bottom and replicates
///         the same ordering.
///
///         **Namespace:** `base.policy_registry`. The ERC-7201 location is
///         `keccak256(abi.encode(uint256(keccak256("base.policy_registry")) - 1)) & ~bytes32(uint256(0xff))`.
///
///         **Packed policy slot layout** (field `policies[id]`):
///           [255]      exists flag (high bit of `existsByte`, never cleared)
///           [254:248]  unused bits within `existsByte` (always zero)
///           [247:160]  reserved (`reservedMiddle`, always zero)
///           [159:0]    admin address; zero after renounceAdmin
///         Solidity packs the `PolicyPacked` struct LSB-first into a single
///         256-bit slot, so the struct field declaration order IS the binary
///         layout spec — the Rust impl mirrors the field order and types
///         (`Address` then `uint88` then `uint8`) with no comment-vs-code
///         drift surface. The bit-255 exists location is preserved as a
///         deliberate constraint (storage layout is frozen — see
///         `EXISTS_FLAG_BYTE` for the footgun this creates and the helpers
///         that hide it).
///         The exists bit survives renunciation, so an unset `existsByte`
///         reliably means "never created". PolicyType is NOT stored —
///         it is recovered from `policyId`'s top byte.
///
///         **Polymorphism non-goal.** This struct holds the admin'd
///         ALLOWLIST/BLOCKLIST policy shape. Future composite policy
///         types (e.g. UNION/INTERSECT, immutable + multi-reference)
///         must NOT be overloaded onto this struct: Solidity's lack of
///         sum-types means doing so would force an awkward worst-of-both
///         layout. When composite types land, they get their own struct
///         and a parallel `mapping(uint64 => CompositePolicyPacked)`,
///         with the policy ID's top byte routing lookups between
///         mappings.
library MockPolicyRegistryStorage {
    /// @notice Packed storage word for an admin'd policy (ALLOWLIST or
    ///         BLOCKLIST). Solidity LSB-first packing:
    ///           bits   0..159 : admin
    ///           bits 160..247 : reservedMiddle (always zero)
    ///           bits 248..255 : existsByte — only bit 7 (slot bit 255)
    ///                           carries the existence signal
    /// @dev    The `existsByte` field is a single byte but only its high
    ///         bit (= slot bit 255) is meaningful. This is a deliberate
    ///         consequence of preserving the bit-255 existence-flag
    ///         location while still expressing the slot as a Solidity
    ///         packed struct (Solidity has no arbitrary-width sub-byte
    ///         types, so a single-bit field at byte 31 has to ride along
    ///         in a `uint8`). **Direct writes to `existsByte` are
    ///         footgun-prone** — `existsByte = 1` lands the flag at slot
    ///         bit 248, NOT bit 255. Use `newPolicy()` to construct and
    ///         `existsSet()` to read; the helpers always write
    ///         `EXISTS_FLAG_BYTE` and read via inequality with zero.
    ///
    ///         The `exists` signal is what lets the registry distinguish
    ///         "renounced" (admin zero, existsByte != 0) from "never
    ///         created" (admin zero, existsByte == 0). Without it,
    ///         BLOCKLIST policies with renounced admins would collide
    ///         with the zero-default.
    struct PolicyPacked {
        address admin;
        uint88 reservedMiddle;
        uint8 existsByte;
    }

    /// @notice The byte value `existsByte` must hold to encode
    ///         "exists = true" while preserving the canonical bit-255
    ///         existence-flag location. `0x80` sets bit 7 of the byte
    ///         at slot position 31, which equals slot bit 255.
    /// @dev    The `newPolicy` constructor always writes this value
    ///         when initializing a struct; reads check for non-zero via
    ///         `existsSet`. The `newPolicy` / `existsSet` helpers are
    ///         the only sanctioned API for the existence flag.
    uint8 internal constant EXISTS_FLAG_BYTE = 0x80;

    /// @notice Constructs a new `PolicyPacked` with the existence flag
    ///         set in the canonical bit-255 position.
    /// @dev    Always use this constructor instead of struct-literal
    ///         initialization — direct `existsByte = ...` writes risk
    ///         landing the flag at the wrong bit.
    function newPolicy(address admin) internal pure returns (PolicyPacked memory) {
        return PolicyPacked({admin: admin, reservedMiddle: 0, existsByte: EXISTS_FLAG_BYTE});
    }

    /// @notice Whether `packed` has its existence flag set.
    /// @dev    Tolerant of any non-zero `existsByte` value (in case a
    ///         buggy writer lands a bit anywhere in the byte) — the
    ///         layout-pin tests catch wrong bit positions, so this
    ///         helper's job is just to be a correct-by-construction
    ///         existence check at runtime.
    function existsSet(PolicyPacked memory packed) internal pure returns (bool) {
        return packed.existsByte != 0;
    }

    /// @custom:storage-location erc7201:base.policy_registry
    struct Layout {
        // Packed admin + exists flag via the `PolicyPacked` struct; see
        // the struct definition and the header for the bit layout.
        mapping(uint64 policyId => PolicyPacked packed) policies;
        // ALLOWLIST member: true → authorized. BLOCKLIST member: true → blocked.
        mapping(uint64 policyId => mapping(address account => bool)) members;
        // Staged pending admin for in-flight two-step admin transfers.
        mapping(uint64 policyId => address pendingAdmin) pendingAdmins;
        // Global monotonic counter for the low 56 bits of every policy ID.
        // Starts at 0; lazily advanced to 2 on the first `createPolicy`
        // call, which writes the ALWAYS_ALLOW / ALWAYS_BLOCK built-ins
        // into counters 0 and 1 before consuming counter 2 for the new
        // custom policy.
        uint56 nextCounter;
    }

    // keccak256(abi.encode(uint256(keccak256("base.policy_registry")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0x00503aeb06982fa1fe3151dc68f90b3946c55c449dfd447e49dcaece71ba4a00;

    // ============================================================
    //                     SLOT OFFSETS WITHIN LAYOUT
    // ============================================================
    // Solidity allocates struct fields sequentially starting at the struct's
    // base slot. These constants name each field's offset from STORAGE_LOCATION
    // so the Rust impl can derive member slots via keccak256(key, baseSlot).
    // They MUST stay in sync with the field order of Layout above.

    uint256 internal constant POLICIES_OFFSET = 0;
    uint256 internal constant MEMBERS_OFFSET = 1;
    uint256 internal constant PENDING_ADMINS_OFFSET = 2;
    uint256 internal constant NEXT_COUNTER_OFFSET = 3;

    /// @notice Absolute slot for a top-level field of `Layout`.
    function slotOf(uint256 offset) internal pure returns (bytes32) {
        return bytes32(uint256(STORAGE_LOCATION) + offset);
    }

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Returns the storage location derived per the ERC-7201 formula.
    ///         Used in tests to assert the hardcoded STORAGE_LOCATION is correct.
    function derivedLocation() internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256("base.policy_registry")) - 1)) & ~bytes32(uint256(0xff));
    }

    // ============================================================
    //                     TOP-LEVEL FIELD SLOTS
    // ============================================================
    // Convenience wrappers around `slotOf(OFFSET)` so test callers (and
    // the Rust impl validator) can read each declared field without
    // remembering the offset constant.

    // forgefmt: disable-start
    function policiesBaseSlot() internal pure returns (bytes32) { return slotOf(POLICIES_OFFSET); }
    function membersBaseSlot() internal pure returns (bytes32) { return slotOf(MEMBERS_OFFSET); }
    function pendingAdminsBaseSlot() internal pure returns (bytes32) { return slotOf(PENDING_ADMINS_OFFSET); }
    function nextCounterSlot() internal pure returns (bytes32) { return slotOf(NEXT_COUNTER_OFFSET); }

        // forgefmt: disable-end

    // ============================================================
    //                     MAPPING MEMBER SLOTS
    // ============================================================
    // Mapping value slots derive as keccak256(abi.encode(key, baseSlot))
    // where `key` is ABI-padded to 32 bytes. uint64 keys are zero-padded
    // to the left up to 32 bytes by abi.encode. Nested mappings hash the
    // outer key first to obtain an inner base slot, then hash the inner
    // key against that.

    /// @notice Slot of `policies[policyId]` (the packed `PolicyPacked`
    ///         struct, a single 256-bit word — admin in bits 0..159, exists
    ///         flag at bit 255).
    function policySlot(uint64 policyId) internal pure returns (bytes32) {
        return keccak256(abi.encode(policyId, policiesBaseSlot()));
    }

    /// @notice Slot of `members[policyId][account]` (the bool membership flag).
    function policyMemberSlot(uint64 policyId, address account) internal pure returns (bytes32) {
        bytes32 perPolicy = keccak256(abi.encode(policyId, membersBaseSlot()));
        return keccak256(abi.encode(account, perPolicy));
    }

    /// @notice Slot of `pendingAdmins[policyId]`.
    function pendingAdminSlot(uint64 policyId) internal pure returns (bytes32) {
        return keccak256(abi.encode(policyId, pendingAdminsBaseSlot()));
    }

    // ============================================================
    //                     PACKED-SLOT CODECS
    // ============================================================
    // Production code accesses `policies[id]` via the `PolicyPacked`
    // struct's named fields — Solidity handles the bit math automatically.
    // These pure codecs operate on a raw `uint256` (what `vm.load` returns
    // for the slot) and exist for test-side use only: layout-pin tests
    // that read the raw slot bytes can use them to extract fields without
    // re-deriving the shifts at every callsite.
    //
    // The roundtrip tests in `MockPolicyRegistrySlotHelpers.t.sol` verify
    // that these codecs' bit math matches Solidity's struct packing — so
    // a codec drifting away from the canonical struct layout fails CI.

    /// @notice Bit position of the `exists` flag within the packed slot.
    ///         Equals the high bit of `existsByte` (bit 7 of byte 31 =
    ///         slot bit 255). Preserved at this location as a deliberate
    ///         frozen-layout constraint.
    uint256 internal constant EXISTS_BIT = 255;

    /// @notice Extracts the policy admin (low 160 bits) from the packed slot.
    function policyAdminFromPacked(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed));
    }

    /// @notice Reads the exists flag. Lets tests distinguish "renounced"
    ///         (exists set, admin zero) from "never created" (slot zero).
    function policyExistsFromPacked(uint256 packed) internal pure returns (bool) {
        return (packed >> EXISTS_BIT) & 1 != 0;
    }

    /// @notice Composes a packed slot from an admin (exists bit always set).
    ///         Matches the binary layout Solidity emits for
    ///         `PolicyPacked({admin: admin, exists: true})`.
    function packPolicy(address admin) internal pure returns (uint256) {
        return (uint256(1) << EXISTS_BIT) | uint256(uint160(admin));
    }

    // ============================================================
    //                     POLICY-ID CODEC
    // ============================================================
    // Encoding: top byte = uint8(PolicyType); low 56 bits = counter.
    // Counters 0 and 1 belong to the ALWAYS_ALLOW / ALWAYS_BLOCK built-ins
    // (written by the registry on its first `createPolicy` call); custom
    // policies are assigned counter 2 and onward.

    /// @notice Extracts the PolicyType discriminator byte (top 8 bits) from a custom policy ID.
    function policyTypeFromId(uint64 policyId) internal pure returns (uint8) {
        return uint8(policyId >> 56);
    }

    /// @notice Extracts the global counter value (low 56 bits) from a custom policy ID.
    function policyCounterFromId(uint64 policyId) internal pure returns (uint56) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint56(policyId & ((uint64(1) << 56) - 1));
    }

    /// @notice Composes a custom policy ID from a PolicyType discriminator and counter value.
    function packPolicyId(uint8 policyType, uint56 counter) internal pure returns (uint64) {
        return (uint64(policyType) << 56) | uint64(counter);
    }
}
