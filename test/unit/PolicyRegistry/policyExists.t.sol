// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPolicyExistsTest is PolicyRegistryTest {
    function test_policyExists_success_builtinZero() public view {
        assertTrue(policyRegistry.policyExists(0));
    }

    function test_policyExists_success_builtinOne() public view {
        assertTrue(policyRegistry.policyExists(1));
    }

    function test_policyExists_success_falseForUncreated(uint64 policyId) public view {
        vm.assume(policyId > 1);
        assertFalse(policyRegistry.policyExists(policyId));
    }

    function test_policyExists_success_trueAfterCreate(uint8 policyTypeInt) public {
        vm.assume(policyTypeInt == 2 || policyTypeInt == 3);
        IPolicyRegistry.PolicyType pt = IPolicyRegistry.PolicyType(policyTypeInt);
        uint64 policyId = policyRegistry.createPolicy(admin, pt);
        assertTrue(policyRegistry.policyExists(policyId));
    }
}
