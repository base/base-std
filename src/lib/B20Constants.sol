// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title B20Constants
/// @notice Canonical B-20 role and policy-type constants, exposed for compile-time use.
library B20Constants {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 internal constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 internal constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 internal constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");
    bytes32 internal constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bytes32 internal constant TRANSFER_SENDER_POLICY = keccak256("TRANSFER_SENDER_POLICY");
    bytes32 internal constant TRANSFER_RECEIVER_POLICY = keccak256("TRANSFER_RECEIVER_POLICY");
    bytes32 internal constant TRANSFER_EXECUTOR_POLICY = keccak256("TRANSFER_EXECUTOR_POLICY");
    bytes32 internal constant MINT_RECEIVER_POLICY = keccak256("MINT_RECEIVER_POLICY");

    /// @notice Bitmask with all `PausableFeature` bits set (TRANSFER | MINT | BURN).
    uint8 internal constant ALL_FEATURES_PAUSED = 7;

    /// @notice Inclusive lower bound for `B20AssetCreateParams.decimals`. `6` is the
    ///         floor most stablecoin-grade integrations expect; values below it lose
    ///         meaningful unit precision for asset workflows.
    uint8 internal constant MIN_ASSET_DECIMALS = 6;

    /// @notice Inclusive upper bound for `B20AssetCreateParams.decimals`. `18` is the
    ///         ERC-20 community ceiling — every common wallet and indexer renders up to
    ///         18 decimals correctly; going higher risks integration breakage.
    uint8 internal constant MAX_ASSET_DECIMALS = 18;

    /// @notice Inclusive upper bound for the supply cap, and therefore for `totalSupply`.
    ///         `type(uint128).max` also serves as the unbounded ("no cap") sentinel: a cap
    ///         set to this value imposes no practical limit while keeping supply within `uint128`.
    uint256 internal constant MAX_SUPPLY_CAP = type(uint128).max;
}
