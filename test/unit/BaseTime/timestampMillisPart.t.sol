// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeTest} from "base-std-test/lib/BaseTimeTest.sol";

contract BaseTimeTimestampMillisPartTest is BaseTimeTest {
    /// @notice Verifies timestampMillisPart returns zero before any write
    /// @dev Default state of slot 0 on a freshly etched predeploy.
    function test_timestampMillisPart_success_zeroByDefault() public view {
        assertEq(baseTime.timestampMillisPart(), 0, "timestampMillisPart must default to zero");
    }

    /// @notice Verifies timestampMillisPart returns the stored millisecond component
    /// @dev Fuzzes over the valid set {0, 200, 400, 600, 800}.
    function test_timestampMillisPart_success_returnsStored(uint256 seed) public {
        uint16 part = _validMillisPart(seed);
        _setTimestampMillisPart(part);
        assertEq(baseTime.timestampMillisPart(), part, "timestampMillisPart must return the stored value");
    }
}
