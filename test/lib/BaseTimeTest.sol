// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "base-std-test/lib/BaseTest.sol";
import {MockBaseTimeStorage} from "base-std-test/lib/mocks/MockBaseTimeStorage.sol";

import {IBaseTime} from "base-std/interfaces/IBaseTime.sol";
import {StdPredeploys} from "base-std/StdPredeploys.sol";

/// @notice Base test contract for `IBaseTime` unit tests.
///
/// Inherits the BaseTime etch wiring from `BaseTest`; adds the predeploy
/// handle and a helper that writes the millisecond component directly,
/// standing in for the protocol's `tx[1]` deposit.
contract BaseTimeTest is BaseTest {
    // -- Predeploy handle --
    IBaseTime internal baseTime = StdPredeploys.BASE_TIME;

    /// @notice Writes `part` into BaseTime's `timestampMillisPart` slot.
    function _setTimestampMillisPart(uint16 part) internal {
        vm.store(
            StdPredeploys.BASE_TIME_ADDRESS, MockBaseTimeStorage.TIMESTAMP_MILLIS_PART_SLOT, bytes32(uint256(part))
        );
    }

    /// @notice Maps a fuzz seed to a valid millisecond component (0, 200, 400, 600, or 800).
    function _validMillisPart(uint256 seed) internal pure returns (uint16) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(bound(seed, 0, 4) * 200);
    }
}
