// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeTest} from "base-std-test/lib/BaseTimeTest.sol";

contract BaseTimeVersionTest is BaseTimeTest {
    /// @notice Verifies version returns the predeploy's semantic version
    function test_version_success_returnsSemver() public view {
        assertEq(baseTime.version(), "1.0.0", "version must equal 1.0.0");
    }
}
