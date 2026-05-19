// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "test/lib/BaseTest.sol";

import {IActivationRegistry} from "src/interfaces/IActivationRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `IActivationRegistry` unit tests.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the registry handle, the activation admin
/// resolution, and the activate helper.
contract ActivationRegistryTest is BaseTest {
    // -- Precompile handle --
    IActivationRegistry internal activationRegistry = StdPrecompiles.ACTIVATION_REGISTRY;

    /// @notice The activation admin returned by the precompile. Resolved
    /// in `setUp` (after the mock etch) so tests can prank as the admin
    /// without hardcoding the address.
    address internal activationAdmin;

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();

        // TODO(mock PR): activationAdmin = activationRegistry.admin();
        // vm.label(activationAdmin, "activationAdmin");
    }

    // -- Action wrappers --

    /// @notice Activate `feature` with explicit caller.
    function _activate(address caller, bytes32 feature) internal {
        vm.prank(caller);
        activationRegistry.activate(feature);
    }

    /// @notice Activate `feature` as the activation admin (resolved in `setUp`).
    function _activate(bytes32 feature) internal {
        _activate(activationAdmin, feature);
    }
}
