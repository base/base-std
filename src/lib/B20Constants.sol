// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title B20Constants
/// @notice Canonical B-20 role and policy-type constants, exposed for compile-time use.
library B20Constants {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 internal constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 internal constant BURN_BLOCKED_ROLE = keccak256("BURN_BLOCKED_ROLE");
    bytes32 internal constant SEIZE_ROLE = keccak256("SEIZE_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 internal constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");
    bytes32 internal constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bytes32 internal constant TRANSFER_SENDER_POLICY = keccak256("TRANSFER_SENDER_POLICY");
    bytes32 internal constant TRANSFER_RECEIVER_POLICY = keccak256("TRANSFER_RECEIVER_POLICY");
    bytes32 internal constant TRANSFER_EXECUTOR_POLICY = keccak256("TRANSFER_EXECUTOR_POLICY");
    bytes32 internal constant MINT_RECEIVER_POLICY = keccak256("MINT_RECEIVER_POLICY");
    bytes32 internal constant SEIZE_EXEMPT_POLICY = keccak256("SEIZE_EXEMPT_POLICY");
    bytes32 internal constant SEIZE_RECEIVER_POLICY = keccak256("SEIZE_RECEIVER_POLICY");

    /// @notice High bit of a `uint64` policy ID that inverts the base policy's decision.
    /// @dev    `isAuthorized(base | POLICY_INVERT_BIT, account)` returns the opposite of
    ///         `isAuthorized(base, account)`, and is fail-closed: an inverted ID whose base
    ///         does not exist or is malformed returns `false` rather than authorizing
    ///         everyone. The other queries strip this bit and resolve to the base, so
    ///         `policyExists(base | POLICY_INVERT_BIT) == policyExists(base)` — a token can
    ///         store an inverted policy ID per scope and re-validate it like a plain one.
    ///         A live policy counter occupies only the low 56 bits (the type byte sits at
    ///         `[63:56]`), so bit 63 never collides with an issued ID.
    uint64 internal constant POLICY_INVERT_BIT = uint64(1) << 63;

    /// @notice Returns the negated form of `policyId` by toggling the invert flag, so
    ///         `isAuthorized(invertPolicy(id), account) == !isAuthorized(id, account)` for an
    ///         existing base. Involutive: `invertPolicy(invertPolicy(id)) == id`.
    /// @dev    Pure bit math — no registry call. A composite child set uses this to express
    ///         "NOT on this list", e.g. `INTERSECT[A, invertPolicy(X)]`.
    /// @param  policyId The policy ID to negate.
    /// @return The policy ID with its invert flag toggled.
    function invertPolicy(uint64 policyId) internal pure returns (uint64) {
        return policyId ^ POLICY_INVERT_BIT;
    }

    /// @notice Bitmask with all `PausableFeature` bits set (TRANSFER | MINT | BURN | SEIZE); 15 = 0b1111.
    uint8 internal constant ALL_FEATURES_PAUSED = 15;

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
