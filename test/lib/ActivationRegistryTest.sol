// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";
import {BaseTest} from "base-std-test/lib/BaseTest.sol";

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

/// @notice Base test contract for `IActivationRegistry` unit tests.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the registry handle and resolves the activation
/// admin from the mock in `setUp` so tests can prank as the admin
/// without hardcoding the address. Test bodies that activate features
/// do the `vm.prank` / call inline so the action is visible at the
/// test site.
contract ActivationRegistryTest is BaseTest {
    // -- Precompile handle --
    IActivationRegistry internal activationRegistry = StdPrecompiles.ACTIVATION_REGISTRY;

    /// @notice The activation admin returned by the precompile. Resolved
    /// in `setUp` so tests can prank as the admin without hardcoding it.
    address internal activationAdmin;

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();

        activationAdmin = activationRegistry.admin();
        vm.label(activationAdmin, "activationAdmin");
    }

    /// @notice Filters out feature ids that `BaseTest.setUp` pre-activates.
    /// @dev    Tests that fuzz over arbitrary `bytes32` features and assume
    ///         the feature starts inactive (or that activation is fresh) must
    ///         exclude these so the fuzzer doesn't trip on the bootstrap state.
    function _assumeFreshFeature(bytes32 feature) internal pure {
        vm.assume(feature != ActivationRegistryFeatureList.B20_ASSET);
        vm.assume(feature != ActivationRegistryFeatureList.B20_STABLECOIN);
        vm.assume(feature != ActivationRegistryFeatureList.POLICY_REGISTRY);
    }
}
