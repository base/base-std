// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryActivateRevertOrderTest is ActivationRegistryTest {
    /// @notice Verifies Unauthorized fires before AlreadyActivated when caller is not admin
    ///         and the feature is already activated
    /// @dev Revert order: access-control check precedes state validation; a non-admin caller
    ///      never reaches the AlreadyActivated guard regardless of feature state.
    ///      Fuzz: any caller that is not the activationAdmin, any feature id.
    function test_activate_revertOrder_unauthorized_beats_alreadyActivated(address caller, bytes32 feature) public {
        _assumeValidCaller(caller);
        vm.assume(caller != activationAdmin);
        _assumeFreshFeature(feature);

        // Activate the feature as admin so it is already activated, establishing
        // the precondition that AlreadyActivated *could* fire for an admin caller.
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);

        // A non-admin caller must see Unauthorized, not AlreadyActivated,
        // because the access-control check in activate fires first.
        vm.expectRevert(abi.encodeWithSelector(IActivationRegistry.Unauthorized.selector, caller));
        vm.prank(caller);
        activationRegistry.activate(feature);
    }
}
