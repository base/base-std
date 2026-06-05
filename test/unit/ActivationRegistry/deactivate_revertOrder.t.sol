// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryDeactivateRevertOrderTest is ActivationRegistryTest {
    /// @notice Verifies Unauthorized fires before FeatureNotActivated when caller is not admin
    ///         and the feature is not currently activated
    /// @dev Revert order: access-control check precedes state validation; a non-admin caller
    ///      never reaches the FeatureNotActivated guard regardless of feature state.
    ///      Fuzz: any caller that is not the activationAdmin, any feature id.
    function test_deactivate_revertOrder_unauthorized_beats_featureNotActivated(address caller, bytes32 feature)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(caller != activationAdmin);

        // The feature is not activated (default state), establishing the precondition
        // that FeatureNotActivated *could* fire for an admin caller.

        // A non-admin caller must see Unauthorized, not FeatureNotActivated,
        // because the access-control check in deactivate fires first.
        vm.expectRevert(abi.encodeWithSelector(IActivationRegistry.Unauthorized.selector, caller));
        vm.prank(caller);
        activationRegistry.deactivate(feature);
    }
}
