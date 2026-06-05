// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";
import {MockActivationRegistryStorage} from "base-std-test/lib/mocks/MockActivationRegistryStorage.sol";

contract ActivationRegistryDeactivateTest is ActivationRegistryTest {
    /// @notice Verifies deactivate reverts when called by any non-admin caller
    /// @dev Access control: only the activation admin may deactivate; checks Unauthorized(caller) error
    function test_deactivate_revert_unauthorized(address caller, bytes32 feature) public {
        _assumeValidCaller(caller);
        vm.assume(caller != activationAdmin);
        vm.assume(!activationRegistry.isActivated(feature));

        // Activate the feature first so the auth check is reached before any
        // state-based revert. The auth check fires first in source order, so
        // skipping this step would still revert with Unauthorized — but
        // activating documents that the unauthorized rejection is independent
        // of the feature's current state.
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);

        vm.expectRevert(abi.encodeWithSelector(IActivationRegistry.Unauthorized.selector, caller));
        vm.prank(caller);
        activationRegistry.deactivate(feature);
    }

    /// @notice Verifies deactivate reverts when invoked on a feature that is not activated
    /// @dev Deactivation is not idempotent; checks FeatureNotActivated(feature) error
    function test_deactivate_revert_featureNotActivated(bytes32 feature) public {
        vm.assume(!activationRegistry.isActivated(feature));

        vm.expectRevert(abi.encodeWithSelector(IActivationRegistry.FeatureNotActivated.selector, feature));
        vm.prank(activationAdmin);
        activationRegistry.deactivate(feature);
    }

    /// @notice Verifies deactivate flips isActivated(feature) from true to false
    /// @dev Successful deactivation persists for future isActivated queries. Paired
    ///      slot: features[feature] slot must zero out after deactivate.
    function test_deactivate_success_setsInactive(bytes32 feature) public {
        vm.assume(!activationRegistry.isActivated(feature));

        vm.prank(activationAdmin);
        activationRegistry.activate(feature);
        assertTrue(activationRegistry.isActivated(feature), "feature must be activated before deactivate");

        vm.prank(activationAdmin);
        activationRegistry.deactivate(feature);

        assertFalse(activationRegistry.isActivated(feature), "feature must be inactive after deactivate");
        assertEq(
            vm.load(address(activationRegistry), MockActivationRegistryStorage.featureSlot(feature)),
            bytes32(0),
            "features[feature] slot must be cleared after deactivate"
        );
    }

    /// @notice Verifies deactivate emits FeatureDeactivated(feature, caller)
    /// @dev Event integrity: indexed feature and caller match the call
    function test_deactivate_success_emitsFeatureDeactivated(bytes32 feature) public {
        vm.assume(!activationRegistry.isActivated(feature));

        vm.prank(activationAdmin);
        activationRegistry.activate(feature);

        vm.expectEmit(address(activationRegistry));
        emit IActivationRegistry.FeatureDeactivated(feature, activationAdmin);
        vm.prank(activationAdmin);
        activationRegistry.deactivate(feature);
    }
}
