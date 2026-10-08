// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockBaseTimeStorage
/// @notice Slot-layout constants for the `MockBaseTime` reference implementation.
///
/// @dev    BaseTime is a Solidity predeploy, not a native precompile, so its layout is the
///         compiler's sequential layout rather than an ERC-7201 namespace: `uint16
///         timestampMillisPart` occupies the low-order 2 bytes of slot 0.
library MockBaseTimeStorage {
    /// @notice Slot holding `timestampMillisPart`.
    bytes32 internal constant TIMESTAMP_MILLIS_PART_SLOT = bytes32(uint256(0));
}
