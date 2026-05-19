// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryDeactivateTest is ActivationRegistryTest {
    /// @notice Verifies deactivate reverts when called by any non-admin caller
    /// @dev Access control: only the activation admin may deactivate; checks Unauthorized(caller) error
    function test_deactivate_revert_unauthorized(address caller, bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies deactivate reverts when invoked on a feature that is not activated
    /// @dev Deactivation is not idempotent; checks FeatureNotActivated(feature) error
    function test_deactivate_revert_featureNotActivated(bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies deactivate flips isActivated(feature) from true to false
    /// @dev Successful deactivation persists for future isActivated queries
    function test_deactivate_success_setsInactive(bytes32 feature) public {
        // unimplemented
    }

    /// @notice Verifies deactivate emits FeatureDeactivated(feature, caller)
    /// @dev Event integrity: indexed feature and caller match the call
    function test_deactivate_success_emitsFeatureDeactivated(bytes32 feature) public {
        // unimplemented
    }
}
