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
///           [255:168]  unused
///           [167:8]    admin address (160 bits). Zero after renounceAdmin.
///           [7:0]      PolicyType (ALLOWLIST = 2, BLOCKLIST = 3).
///                      Both values are non-zero, so `policies[id] == 0`
///                      reliably means the policy was never created.
library MockPolicyRegistryStorage {
    /// @custom:storage-location erc7201:base.policy_registry
    struct Layout {
        // Each entry packs admin + PolicyType into a single uint256.
        // packed == 0 means the policy was never created (see packed layout above).
        mapping(uint64 policyId => uint256 packed) policies;
        // ALLOWLIST: true → account IS authorized.
        // BLOCKLIST: true → account IS blocked (NOT authorized).
        mapping(uint64 policyId => mapping(address account => bool)) members;
        // Staged pending admin for in-flight two-step admin transfers.
        mapping(uint64 policyId => address pendingAdmin) pendingAdmins;
        // Global monotonic counter for the low 56 bits of custom policy IDs.
        // MockPolicyRegistry floors this to 2 on first read/write so the first
        // custom ID explicitly reserves built-ins 0 and 1.
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

    /// @notice Slot of `policies[policyId]` (the packed admin+type uint256).
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
    // `policies[id]` packs an admin address and a PolicyType into a
    // single uint256:
    //   [255:168]  unused
    //   [167:8]    admin address (160 bits, zero after renounceAdmin)
    //   [7:0]      PolicyType (ALLOWLIST = 2, BLOCKLIST = 3)
    // Both defined PolicyType values are non-zero, so `policies[id] == 0`
    // reliably means "never created".

    /// @notice Extracts the policy admin address (bits 8..167) from the packed slot.
    function policyAdminFromPacked(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed >> 8));
    }

    /// @notice Extracts the PolicyType byte (bits 0..7) from the packed slot.
    function policyTypeFromPacked(uint256 packed) internal pure returns (uint8) {
        return uint8(packed);
    }

    /// @notice Composes the packed slot value from its two fields.
    /// @dev `policyType` is the raw uint8 of the `IPolicyRegistry.PolicyType`
    ///      enum value the registry stores.
    function packPolicy(address admin, uint8 policyType) internal pure returns (uint256) {
        return (uint256(uint160(admin)) << 8) | uint256(policyType);
    }

    // ============================================================
    //                     POLICY-ID CODEC
    // ============================================================
    // Custom policy IDs encode the policy type in the high byte of the
    // uint64 and the global counter in the low 56 bits:
    //   [63:56]  uint8(PolicyType) discriminator
    //   [55:0]   nextCounter value at creation
    //
    // Built-in IDs 0 and 1 (ALWAYS_ALLOW, ALWAYS_BLOCK) are short-
    // circuited in `MockPolicyRegistry` before storage and don't follow
    // this encoding; these codecs decode the bit layout literally
    // regardless.

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
