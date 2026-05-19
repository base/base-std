// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IActivationRegistry} from "src/interfaces/IActivationRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `IActivationRegistry` unit tests.
///
/// `setUp` is mock-vs-live aware: the etch is skipped when the canonical
/// precompile address already has code (live mode under `--fork-url`).
/// In mock mode the mock contract is etched at the canonical address so
/// the same test body executes against either backend without branching.
///
/// The mock contract is added in a follow-up PR; until then, calls to
/// the registry revert at runtime under mock mode. The unit stubs in this
/// spec PR are not yet implemented, so this is intentional.
contract ActivationRegistryTest is Test {
    // -- Actors --
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    /// @notice The activation admin returned by the precompile. Resolved in
    /// `setUp` so tests can prank as the admin without hardcoding the address.
    address internal activationAdmin;

    // -- Precompile handle --
    IActivationRegistry internal activationRegistry = StdPrecompiles.ACTIVATION_REGISTRY;

    // -- Setup --
    function setUp() public virtual {
        vm.label(StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS, "ActivationRegistry");
        vm.label(alice, "alice");
        vm.label(attacker, "attacker");

        // TODO(mock PR): if (StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS.code.length == 0) {
        //     vm.etch(StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS, type(MockActivationRegistry).runtimeCode);
        // }
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
