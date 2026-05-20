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
}
