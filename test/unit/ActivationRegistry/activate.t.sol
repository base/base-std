// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";
import {MockActivationRegistryStorage} from "base-std-test/lib/mocks/MockActivationRegistryStorage.sol";

contract ActivationRegistryActivateTest is ActivationRegistryTest {
    /// @notice Verifies activate reverts when called by any non-admin caller
    /// @dev Access control: only the activation admin may activate; checks Unauthorized(caller) error
    function test_activate_revert_unauthorized(address caller, bytes32 feature) public {
        _assumeValidCaller(caller);
        vm.assume(caller != activationAdmin);

        vm.expectRevert(abi.encodeWithSelector(IActivationRegistry.Unauthorized.selector, caller));
        vm.prank(caller);
        activationRegistry.activate(feature);
    }

    /// @notice Verifies activate reverts when invoked on a feature that is already activated
    /// @dev Activation is not idempotent; checks AlreadyActivated(feature) error
    function test_activate_revert_alreadyActivated(bytes32 feature) public {
        vm.assume(!activationRegistry.isActivated(feature));

        vm.prank(activationAdmin);
        activationRegistry.activate(feature);

        vm.expectRevert(abi.encodeWithSelector(IActivationRegistry.AlreadyActivated.selector, feature));
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);
    }

    /// @notice Verifies activate flips isActivated(feature) from false to true
    /// @dev Successful activation persists for future isActivated queries. Paired
    ///      slot: features[feature] slot must equal bytes32(uint256(1)).
    function test_activate_success_setsActivated(bytes32 feature) public {
        vm.assume(!activationRegistry.isActivated(feature));
        assertFalse(activationRegistry.isActivated(feature), "feature must start inactive");

        vm.prank(activationAdmin);
        activationRegistry.activate(feature);

        assertTrue(activationRegistry.isActivated(feature), "feature must be activated after activate");
        assertEq(
            uint256(vm.load(address(activationRegistry), MockActivationRegistryStorage.featureSlot(feature))),
            uint256(1),
            "features[feature] slot must be set to 1 after activate"
        );
    }

    /// @notice Verifies activate emits FeatureActivated(feature, caller)
    /// @dev Event integrity: indexed feature and caller match the call
    function test_activate_success_emitsFeatureActivated(bytes32 feature) public {
        vm.assume(!activationRegistry.isActivated(feature));

        vm.expectEmit(address(activationRegistry));
        emit IActivationRegistry.FeatureActivated(feature, activationAdmin);
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);
    }
}
