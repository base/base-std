// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockActivationRegistryStorage
/// @notice Slot-layout library for the `MockActivationRegistry` reference implementation.
///
///         Every piece of mutable activation-registry state lives in this struct at
///         a single ERC-7201-namespaced location, so the Rust precompile implementation
///         has an unambiguous, audit-grep-able source of truth for which slot
///         holds what.
///
/// @dev    **Why ERC-7201 over flat unstructured storage?**
///         The struct field ORDER is the slot layout. There is no separate list
///         of slot constants that can drift out of sync with the fields they
///         describe. The Rust impl reads this struct top-to-bottom and replicates
///         the same ordering.
///
///         **Namespace:** `base.activation_registry`. The ERC-7201 location is
///         `keccak256(abi.encode(uint256(keccak256("base.activation_registry")) - 1)) & ~bytes32(uint256(0xff))`.
///
///         The admin address is NOT stored: the production precompile and this
///         mock both return a hardcoded constant from `admin()` (see
///         `MockActivationRegistry.ADMIN`). Only the feature-activation map needs
///         storage backing.
library MockActivationRegistryStorage {
    /// @custom:storage-location erc7201:base.activation_registry
    struct Layout {
        // True iff `feature` is currently activated. The default-false slot
        // value is the same observable state as "never activated", per the
        // IActivationRegistry contract that `isActivated` returns `false`
        // (rather than reverting) for unknown features. `activate` flips a
        // slot to true; `deactivate` flips it back to false.
        mapping(bytes32 feature => bool active) features;
    }

    // keccak256(abi.encode(uint256(keccak256("base.activation_registry")) - 1)) & ~bytes32(uint256(0xff))
    // Verified against the computation in derivedLocation() below.
    bytes32 internal constant STORAGE_LOCATION = 0x43ee1bbe25e988521cccd8b2c8fbd38c8287ebff8e074e825a70dfd3885cce00;

    // ============================================================
    //                     SLOT OFFSETS WITHIN LAYOUT
    // ============================================================
    // Solidity allocates struct fields sequentially starting at the struct's
    // base slot. These constants name each field's offset from STORAGE_LOCATION
    // so the Rust impl can derive member slots via keccak256(key, baseSlot).
    // They MUST stay in sync with the field order of Layout above.

    uint256 internal constant FEATURES_OFFSET = 0;

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
        return keccak256(abi.encode(uint256(keccak256("base.activation_registry")) - 1)) & ~bytes32(uint256(0xff));
    }

    // ============================================================
    //                     TOP-LEVEL FIELD SLOTS
    // ============================================================
    // Convenience wrappers around `slotOf(OFFSET)` so test callers (and
    // the Rust impl validator) can read each declared field without
    // remembering the offset constant.

    function featuresBaseSlot() internal pure returns (bytes32) {
        return slotOf(FEATURES_OFFSET);
    }

    // ============================================================
    //                     MAPPING MEMBER SLOTS
    // ============================================================
    // Mapping value slots derive as keccak256(abi.encode(key, baseSlot))
    // where `key` is ABI-padded to 32 bytes. bytes32 keys are passed
    // through unchanged.

    /// @notice Slot of `features[feature]` (the bool activation flag).
    function featureSlot(bytes32 feature) internal pure returns (bytes32) {
        return keccak256(abi.encode(feature, featuresBaseSlot()));
    }
}
