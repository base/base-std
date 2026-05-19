// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryActivateTest is ActivationRegistryTest {
    /// @notice Verifies activate reverts when called by any non-admin caller
    /// @dev Access control: only the activation admin may activate; checks Unauthorized(caller) error
    function test_activate_revert_unauthorized(address caller, bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies activate reverts when invoked on a feature that is already activated
    /// @dev Activation is not idempotent; checks AlreadyActivated(feature) error
    function test_activate_revert_alreadyActivated(bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies activate flips isActivated(feature) from false to true
    /// @dev Successful activation persists for future isActivated queries
    function test_activate_success_setsActivated(bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies activate emits FeatureActivated(feature, caller)
    /// @dev Event integrity: indexed feature and caller match the call
    function test_activate_success_emitsFeatureActivated(bytes32 feature) public {
        // unimplemented
    }
}
