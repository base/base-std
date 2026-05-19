// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "test/lib/BaseTest.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `IPolicyRegistry` unit tests.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the registry handle. Test bodies that need to set
/// up policies or rotate admins do so inline so the `vm.prank` / call
/// is visible at the test site rather than hidden behind a wrapper.
contract PolicyRegistryTest is BaseTest {
    // -- Precompile handle --
    IPolicyRegistry internal policyRegistry = StdPrecompiles.POLICY_REGISTRY;
}
