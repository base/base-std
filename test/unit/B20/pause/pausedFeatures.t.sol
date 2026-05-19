// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20PausedFeaturesTest is B20Test {
    /// @notice Verifies pausedFeatures returns an empty array on a freshly-created token
    /// @dev Default state: no features paused
    function test_pausedFeatures_success_emptyByDefault() public {
        // unimplemented
    }

    /// @notice Verifies pausedFeatures returns the set of features paused via pause
    /// @dev Readback after one or more pause calls
    function test_pausedFeatures_success_reflectsPauseCalls() public {
        // unimplemented
    }

    /// @notice Verifies pausedFeatures returns the set minus features removed via unpause
    /// @dev Readback after partial unpause
    function test_pausedFeatures_success_reflectsUnpauseCalls() public {
        // unimplemented
    }
}
