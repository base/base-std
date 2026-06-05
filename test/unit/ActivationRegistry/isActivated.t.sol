// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryIsActivatedTest is ActivationRegistryTest {
    /// @notice Verifies isActivated returns false for any feature id that has never been activated
    /// @dev Default state across the entire bytes32 id space. IActivationRegistry NatSpec L45-47
    ///      explicitly carves this out: "not raised by `isActivated`, which returns `false`
    ///      instead." Regression test for L-04 (was: revert "not implemented").
    function test_isActivated_success_defaultFalse(bytes32 feature) public view {
        _assumeFreshFeature(feature);
        assertFalse(activationRegistry.isActivated(feature), "isActivated must return false for unactivated features");
    }

    /// @notice Verifies isActivated returns true after activate(feature) succeeds
    /// @dev State flip is observable immediately on the same feature id
    function test_isActivated_success_trueAfterActivate(bytes32 feature) public {
        _assumeFreshFeature(feature);
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);
        assertTrue(activationRegistry.isActivated(feature), "isActivated must return true after activate");
    }
}
