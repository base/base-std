// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Canonical B-20 role and policy-type identifier constants.
///         Declared as a library (not on the contract) so tests and
///         downstream tooling can reference them at compile time via
///         `MINT_ROLE` etc. — Solidity's `public constant`
///         on a contract is only accessible via instance (e.g.
///         `token.MINT_ROLE()`), which doesn't work where the token
///         doesn't yet exist (factory creation tests, initCall
///         construction).
/// @dev    `MockB20` re-exposes each value as `bytes32 public constant`
///         to satisfy `IB20`'s view-function ABI; the library is the
///         single source of truth, the public constants delegate.
library B20Constants {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 internal constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 internal constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");
    bytes32 internal constant BURN_FROM_ROLE = keccak256("BURN_FROM_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 internal constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");
    bytes32 internal constant METADATA_ROLE = keccak256("METADATA_ROLE");

    bytes32 internal constant TRANSFER_SENDER_POLICY = keccak256("TRANSFER_SENDER_POLICY");
    bytes32 internal constant TRANSFER_RECEIVER_POLICY = keccak256("TRANSFER_RECEIVER_POLICY");
    bytes32 internal constant TRANSFER_EXECUTOR_POLICY = keccak256("TRANSFER_EXECUTOR_POLICY");
    bytes32 internal constant MINT_RECEIVER_POLICY = keccak256("MINT_RECEIVER_POLICY");
}
