// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20IsPausedTest is B20Test {
    /// @notice Verifies isPaused returns false for every feature on a freshly-created token
    /// @dev Default state across all PausableFeature enum values
    function test_isPaused_success_falseByDefault(uint8 featureInt) public {
        // unimplemented
    }

    /// @notice Verifies isPaused returns true after the feature is paused
    /// @dev State flip is observable per-feature
    function test_isPaused_success_trueAfterPause(uint8 featureInt) public {
        // unimplemented
    }

    /// @notice Verifies isPaused returns false again after the feature is unpaused
    /// @dev State flip back to inactive
    function test_isPaused_success_falseAfterUnpause(uint8 featureInt) public {
        // unimplemented
    }
}
