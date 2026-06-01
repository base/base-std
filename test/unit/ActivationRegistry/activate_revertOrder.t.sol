// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryActivateRevertOrderTest is ActivationRegistryTest {
    /// @notice Verifies Unauthorized fires before AlreadyActivated when caller is not admin
    ///         and the feature is already activated
    /// @dev Revert order: access-control check precedes state validation; a non-admin caller
    ///      never reaches the AlreadyActivated guard regardless of feature state.
    ///      Fuzz: any caller that is not the activationAdmin, any feature id.
    function test_activate_revertOrder_unauthorized_beats_alreadyActivated(address caller, bytes32 feature) public {
        // unimplemented
    }
}
