// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryCompositeChildPolicyLimitsTest is PolicyRegistryTest {
    /// @notice MIN_COMPOSITE_CHILD_POLICIES() returns the registry's composite child-policy floor.
    function test_minCompositeChildPolicies_success() public view {
        assertEq(policyRegistry.MIN_COMPOSITE_CHILD_POLICIES(), MIN_CHILD_POLICIES);
    }

    /// @notice MAX_COMPOSITE_CHILD_POLICIES() returns the registry's composite child-policy cap.
    function test_maxCompositeChildPolicies_success() public view {
        assertEq(policyRegistry.MAX_COMPOSITE_CHILD_POLICIES(), MAX_CHILD_POLICIES);
    }
}
