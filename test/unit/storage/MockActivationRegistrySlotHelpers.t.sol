// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";
import {MockActivationRegistryStorage} from "base-std-test/lib/mocks/MockActivationRegistryStorage.sol";

/// @notice Self-tests for `MockActivationRegistryStorage`'s slot-derivation helpers.
///
/// @dev    Each test mutates registry state via the IActivationRegistry surface,
///         reads the helper-computed slot via `vm.load`, and asserts the slot
///         encodes the same value the surface returns.
contract MockActivationRegistrySlotHelpersTest is ActivationRegistryTest {
    /// @notice Verifies `featureSlot(feature)` locates the bool flag set by activate.
    /// @dev    Activate a feature, then read the derived slot — must equal bytes32(uint256(1)).
    function test_featureSlot_success_locatesActivationBit(bytes32 feature) public {
        _assumeFreshFeature(feature);
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);

        assertEq(
            uint256(vm.load(address(activationRegistry), MockActivationRegistryStorage.featureSlot(feature))),
            uint256(1),
            "featureSlot must locate the bool flag set by activate"
        );
    }

    /// @notice Verifies `featureSlot(feature)` is zero for an unactivated feature.
    /// @dev    The default-zero slot value is what backs `isActivated → false`
    ///         for features that were never activated.
    function test_featureSlot_success_zeroForUnactivatedFeature(bytes32 feature) public {
        _assumeFreshFeature(feature);
        assertEq(
            vm.load(address(activationRegistry), MockActivationRegistryStorage.featureSlot(feature)),
            bytes32(0),
            "featureSlot must be zero for an unactivated feature"
        );
    }

    /// @notice Verifies `featureSlot(feature)` re-zeros after a deactivate.
    /// @dev    Cycle the bit: activate sets the slot to 1, deactivate clears it
    ///         back to 0 — the Rust impl must reproduce the same clear-on-deactivate
    ///         storage semantics so subsequent SLOADs read the default value.
    function test_featureSlot_success_zeroAfterDeactivate(bytes32 feature) public {
        _assumeFreshFeature(feature);
        vm.prank(activationAdmin);
        activationRegistry.activate(feature);
        vm.prank(activationAdmin);
        activationRegistry.deactivate(feature);

        assertEq(
            vm.load(address(activationRegistry), MockActivationRegistryStorage.featureSlot(feature)),
            bytes32(0),
            "featureSlot must be cleared after deactivate"
        );
    }

    /// @notice Verifies `featureSlot` slots are disjoint across distinct feature ids.
    /// @dev    Different ids must derive disjoint slots so per-feature writes
    ///         can't alias.
    function test_featureSlot_success_disjointAcrossFeatures(bytes32 featureA, bytes32 featureB) public pure {
        vm.assume(featureA != featureB);

        assertTrue(
            MockActivationRegistryStorage.featureSlot(featureA) != MockActivationRegistryStorage.featureSlot(featureB),
            "featureSlot must differ when feature id differs"
        );
    }

    /// @notice Verifies `featuresBaseSlot()` equals `STORAGE_LOCATION` (offset 0).
    /// @dev    `features` is the first (and only) field of `Layout`, so its base
    ///         slot must equal the namespace root.
    function test_featuresBaseSlot_success_equalsStorageLocation() public pure {
        assertEq(
            MockActivationRegistryStorage.featuresBaseSlot(),
            MockActivationRegistryStorage.STORAGE_LOCATION,
            "featuresBaseSlot must equal STORAGE_LOCATION for the slot-0 field"
        );
    }
}
