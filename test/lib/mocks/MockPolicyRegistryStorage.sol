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
///           [255]      exists flag (set on create, never cleared)
///           [254:160]  unused
///           [159:0]    admin address; zero after renounceAdmin
///         The exists bit survives renunciation, so `policies[id] == 0`
///         reliably means "never created". PolicyType is NOT stored —
///         it is recovered from `policyId`'s top byte.
library MockPolicyRegistryStorage {
    /// @custom:storage-location erc7201:base.policy_registry
    struct Layout {
        // Packed admin + exists flag; see header for layout.
        mapping(uint64 policyId => uint256 packed) policies;
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

    /// @notice Slot of `policies[policyId]` (the packed admin+exists uint256).
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
    // See the library header for the `policies[id]` layout.

    /// @notice Bit position of the existence flag (top bit). Leaves the
    ///         low 160 bits for the admin lane and reserves bits 161-254
    ///         for future fields.
    uint256 internal constant EXISTS_BIT = 255;

    /// @notice Extracts the policy admin (low 160 bits) from the packed slot.
    function policyAdminFromPacked(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed));
    }

    /// @notice Reads the existence flag. Lets tests distinguish "renounced"
    ///         (exists set, admin zero) from "never created" (both zero).
    function policyExistsFromPacked(uint256 packed) internal pure returns (bool) {
        return (packed >> EXISTS_BIT) & 1 != 0;
    }

    /// @notice Composes a packed slot from an admin (exists bit always set).
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
