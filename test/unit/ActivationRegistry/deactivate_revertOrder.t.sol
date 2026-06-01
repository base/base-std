// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryDeactivateRevertOrderTest is ActivationRegistryTest {
    /// @notice Verifies Unauthorized fires before FeatureNotActivated when caller is not admin
    ///         and the feature is not currently activated
    /// @dev Revert order: access-control check precedes state validation; a non-admin caller
    ///      never reaches the FeatureNotActivated guard regardless of feature state.
    ///      Fuzz: any caller that is not the activationAdmin, any feature id.
    function test_deactivate_revertOrder_unauthorized_beats_featureNotActivated(address caller, bytes32 feature)
        public {
        // unimplemented
    }
}
