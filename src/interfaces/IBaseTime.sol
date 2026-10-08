// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IBaseTime
/// @notice Read surface of the BaseTime predeploy, which exposes the millisecond component of the current
///         L2 block timestamp.
interface IBaseTime {
    /*//////////////////////////////////////////////////////////////
                              TIMESTAMP QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Millisecond component (0, 200, 400, 600, or 800) of the current block timestamp. Never reverts.
    ///
    /// @dev Updated by the block's `tx[1]` deposit; earlier in the block it holds the previous block's value.
    ///
    /// @return Millisecond component of the current block timestamp.
    function timestampMillisPart() external view returns (uint16);

    /// @notice Current block timestamp in milliseconds: `block.timestamp * 1000 + timestampMillisPart()`.
    ///         Never reverts.
    ///
    /// @dev Until the block's `tx[1]` deposit executes (e.g. during the `tx[0]` L1-info deposit), this
    ///      combines the current block's seconds with the previous block's millisecond component.
    ///
    /// @return Current block timestamp in milliseconds.
    function timestampMs() external view returns (uint64);

    /// @notice Semantic version of the BaseTime implementation. Never reverts.
    /// @return Semantic version string.
    function version() external view returns (string memory);
}
