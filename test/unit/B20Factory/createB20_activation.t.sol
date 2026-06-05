// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";
import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

/// @notice Pins the activation gating on `createB20`.
///
/// @dev    Two per-variant gates run before any other validation:
///         - `B20_ASSET` — ASSET (and DEFAULT) off
///         - `B20_STABLECOIN` — STABLECOIN off
///         `BaseTest.setUp` activates both by default so the rest of
///         the suite is unaffected; this file deactivates the specific
///         gate under test to exercise the revert path.
contract B20FactoryCreateB20ActivationTest is B20FactoryTest {
    function _deactivate(bytes32 feature) internal {
        vm.prank(StdPrecompiles.ACTIVATION_REGISTRY.admin());
        StdPrecompiles.ACTIVATION_REGISTRY.deactivate(feature);
    }

    /// @notice Verifies createB20(STABLECOIN, ...) reverts with FeatureNotActivated(B20_STABLECOIN)
    ///         when the stablecoin-variant gate is off — but only for STABLECOIN.
    function test_createB20_revert_stablecoinFeatureNotActivated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        _deactivate(ActivationRegistryFeatureList.B20_STABLECOIN);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IActivationRegistry.FeatureNotActivated.selector, ActivationRegistryFeatureList.B20_STABLECOIN
            )
        );
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(_stablecoinParams()), new bytes[](0));
    }

    /// @notice Verifies the stablecoin gate doesn't block ASSET creation — the gates
    ///         are per-variant and isolated.
    function test_createB20_success_stablecoinGateOff_assetStillWorks(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        _deactivate(ActivationRegistryFeatureList.B20_STABLECOIN);

        address token = _createAsset(caller, salt, _assetParams(), new bytes[](0));
        assertTrue(factory.isB20(token), "asset creation must succeed when only the stablecoin gate is off");
    }

    /// @notice Verifies createB20(ASSET, ...) reverts with FeatureNotActivated(B20_ASSET)
    ///         when the asset-variant gate is off.
    function test_createB20_revert_assetFeatureNotActivated_asset(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        _deactivate(ActivationRegistryFeatureList.B20_ASSET);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IActivationRegistry.FeatureNotActivated.selector, ActivationRegistryFeatureList.B20_ASSET
            )
        );
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(_assetParams()), new bytes[](0));
    }

    /// @notice Verifies the asset gate doesn't block STABLECOIN creation.
    function test_createB20_success_assetGateOff_stablecoinStillWorks(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        _deactivate(ActivationRegistryFeatureList.B20_ASSET);

        address token = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertTrue(factory.isB20(token), "stablecoin creation must succeed when only the asset gate is off");
    }

    /// @notice Verifies activation gates do NOT affect the pure address-derivation queries.
    /// @dev    `getB20Address` / `isB20` / `isB20Initialized` are view/pure and must
    ///         remain callable regardless of activation state — they're how off-chain
    ///         tooling reasons about addresses before activation is set up.
    function test_addressQueries_success_unaffectedByActivationState(address sender, bytes32 salt) public {
        _deactivate(ActivationRegistryFeatureList.B20_ASSET);
        _deactivate(ActivationRegistryFeatureList.B20_STABLECOIN);

        // All three should return without reverting.
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, sender, salt);
        assertEq(predicted, predicted, "getB20Address must be callable with all features deactivated");
        assertFalse(
            factory.isB20Initialized(predicted), "isB20Initialized must be callable with all features deactivated"
        );
        // isB20 is a pure prefix check; bool round-trips silently.
        factory.isB20(predicted);
    }
}
