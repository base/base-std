// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryIsActivatedTest is ActivationRegistryTest {
    /// @notice Verifies isActivated returns false for any feature id that has never been activated
    /// @dev Default state across the entire bytes32 id space
    function test_isActivated_success_defaultFalse(bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies isActivated returns true after activate(feature) succeeds
    /// @dev State flip is observable immediately on the same feature id
    function test_isActivated_success_trueAfterActivate(bytes32 feature) public {
        // unimplemented
    }
}
