// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPolicyTypeTest is PolicyRegistryTest {
    /// @notice Verifies policyType reverts for an unknown policy id
    /// @dev Lookup guard for non-existent ids; checks PolicyNotFound() error
    function test_policyType_revert_policyNotFound(uint64 policyId) public {
        vm.assume(policyId > 1);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.policyType(policyId);
    }

    function test_policyType_success_returnsAlwaysAllowForBuiltinZero() public view {
        assertEq(uint8(policyRegistry.policyType(0)), uint8(IPolicyRegistry.PolicyType.ALWAYS_ALLOW));
    }

    function test_policyType_success_returnsAlwaysBlockForBuiltinOne() public view {
        assertEq(uint8(policyRegistry.policyType(1)), uint8(IPolicyRegistry.PolicyType.ALWAYS_BLOCK));
    }

    /// @notice Verifies policyType returns ALLOWLIST for an allowlist policy
    /// @dev Type readback matches the value passed to createPolicy
    function test_policyType_success_returnsAllowlist() public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertEq(uint8(policyRegistry.policyType(policyId)), uint8(IPolicyRegistry.PolicyType.ALLOWLIST));
    }

    /// @notice Verifies policyType returns BLOCKLIST for a blocklist policy
    /// @dev Type readback matches the value passed to createPolicy
    function test_policyType_success_returnsBlocklist() public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        assertEq(uint8(policyRegistry.policyType(policyId)), uint8(IPolicyRegistry.PolicyType.BLOCKLIST));
    }
}
