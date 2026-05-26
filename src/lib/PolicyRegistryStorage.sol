// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

/// @notice Canonical built-in policy ID constants.
///
/// @dev Declared as a library so callers can reference them at compile time
///      via `PolicyRegistryConstants.ALWAYS_ALLOW_ID`. `PolicyRegistry`
///      re-exposes each value as `uint64 public constant` to satisfy the
///      runtime-getter contract; this library is the single source of truth.
library PolicyRegistryConstants {
    /// @notice Built-in policy ID that always authorizes any account.
    /// @dev Encodes as a BLOCKLIST at counter 0 (empty blocklist → allow all).
    uint64 internal constant ALWAYS_ALLOW_ID = 0;

    /// @notice Built-in policy ID that always rejects any account.
    /// @dev Encodes as an ALLOWLIST at counter 1 (empty allowlist → block all).
    uint64 internal constant ALWAYS_BLOCK_ID = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | 1;

    /// @notice Number of built-in policies the registry populates at initialization.
    ///
    /// @dev The global counter is advanced to this value so custom policies
    ///      start at counter `BUILTIN_POLICY_COUNT`.
    uint56 internal constant BUILTIN_POLICY_COUNT = 2;
}

/// @title PolicyRegistryStorage
/// @notice ERC-7201 namespaced storage layout for `PolicyRegistry`.
///
/// @dev Namespace: `base.policy_registry`. Packed policy slot layout (`policies[id]`):
///      [255]      exists flag — set on create, never cleared.
///      [254:160]  unused.
///      [159:0]    admin address; zero after `renounceAdmin`.
///
///      `PolicyType` is NOT stored — it is recovered from the top byte of `policyId`.
library PolicyRegistryStorage {
    /// @custom:storage-location erc7201:base.policy_registry
    struct Layout {
        /// @dev Packed admin + exists flag per policy.
        mapping(uint64 policyId => uint256 packed) policies;
        /// @dev ALLOWLIST member: true → authorized. BLOCKLIST member: true → blocked.
        mapping(uint64 policyId => mapping(address account => bool)) members;
        /// @dev Staged pending admin for in-flight two-step admin transfers.
        mapping(uint64 policyId => address pendingAdmin) pendingAdmins;
        /// @dev Global monotonic counter for the low 56 bits of every policy ID.
        uint56 nextCounter;
    }

    // keccak256(abi.encode(uint256(keccak256("base.policy_registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STORAGE_LOCATION = 0x00503aeb06982fa1fe3151dc68f90b3946c55c449dfd447e49dcaece71ba4a00;

    /// @dev Bit position of the existence flag within a packed policy slot.
    uint256 internal constant EXISTS_BIT = 255;

    function layout() internal pure returns (Layout storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
