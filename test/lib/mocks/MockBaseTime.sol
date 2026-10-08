// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBaseTime} from "base-std/interfaces/IBaseTime.sol";

/// @title MockBaseTime
/// @notice Reference implementation of the `IBaseTime` read surface. Etched at the canonical BaseTime
///         predeploy address via `vm.etch` from `BaseTest.setUp` when that address has no code.
///
/// @dev    No setter: the protocol's `tx[1]` deposit is the only writer on-chain, and tests set the
///         value with `vm.store` (see `BaseTimeTest`).
contract MockBaseTime is IBaseTime {
    /// @notice Semantic version reported by the predeploy.
    string internal constant VERSION = "1.0.0";

    // Slot 0 to match the real predeploy's layout (see `MockBaseTimeStorage`), not ERC-7201.
    uint16 internal _timestampMillisPart;

    /// @inheritdoc IBaseTime
    function timestampMillisPart() external view returns (uint16) {
        return _timestampMillisPart;
    }

    /// @inheritdoc IBaseTime
    function timestampMs() external view returns (uint64) {
        return uint64(block.timestamp * 1000 + _timestampMillisPart);
    }

    /// @inheritdoc IBaseTime
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
