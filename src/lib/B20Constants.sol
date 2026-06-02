// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title B20Constants
/// @notice Canonical B-20 role and policy-type identifier constants, exposed for compile-time use.
library B20Constants {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 internal constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 internal constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 internal constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");
    bytes32 internal constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes32 internal constant SECURITY_OPERATOR_ROLE = keccak256("SECURITY_OPERATOR_ROLE");

    bytes32 internal constant TRANSFER_SENDER_POLICY = keccak256("TRANSFER_SENDER_POLICY");
    bytes32 internal constant TRANSFER_RECEIVER_POLICY = keccak256("TRANSFER_RECEIVER_POLICY");
    bytes32 internal constant TRANSFER_EXECUTOR_POLICY = keccak256("TRANSFER_EXECUTOR_POLICY");
    bytes32 internal constant MINT_RECEIVER_POLICY = keccak256("MINT_RECEIVER_POLICY");

    /// @notice Bitmask with all `PausableFeature` bits set (TRANSFER | MINT | BURN | REDEEM-reserved).
    uint8 internal constant ALL_FEATURES_PAUSED = 15;
}
