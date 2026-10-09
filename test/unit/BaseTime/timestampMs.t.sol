// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeTest} from "base-std-test/lib/BaseTimeTest.sol";

contract BaseTimeTimestampMsTest is BaseTimeTest {
    /// @notice Verifies timestampMs combines block.timestamp seconds with the stored millisecond component
    /// @dev Timestamp is bounded so `ts * 1000 + part` fits in uint64.
    function test_timestampMs_success_combinesSecondsAndMillis(uint256 ts, uint256 seed) public {
        ts = bound(ts, 0, type(uint64).max / 1000 - 1);
        uint16 part = _validMillisPart(seed);
        vm.warp(ts);
        _setTimestampMillisPart(part);
        assertEq(baseTime.timestampMs(), ts * 1000 + part, "timestampMs must equal block.timestamp * 1000 + part");
    }
}
