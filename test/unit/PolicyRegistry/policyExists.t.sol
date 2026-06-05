// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract PolicyRegistryPolicyExistsTest is PolicyRegistryTest {
    function test_policyExists_success_builtinAlwaysAllow() public view {
        assertTrue(policyRegistry.policyExists(PolicyRegistryConstants.ALWAYS_ALLOW_ID));
    }

    function test_policyExists_success_builtinAlwaysBlock() public view {
        assertTrue(policyRegistry.policyExists(PolicyRegistryConstants.ALWAYS_BLOCK_ID));
    }

    /// @notice policyExists returns false for an uncreated id (storage miss).
    function test_policyExists_success_falseForUncreated(uint64 seed) public view {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        assertFalse(policyRegistry.policyExists(policyId));
    }

    /// @notice policyExists returns false for a malformed id.
    function test_policyExists_success_falseForMalformedId(uint64 seed) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertFalse(policyRegistry.policyExists(policyId));
    }

    function test_policyExists_success_trueAfterCreate(uint8 typeIdx) public {
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint64 policyId = policyRegistry.createPolicy(admin, pt);
        assertTrue(policyRegistry.policyExists(policyId));
    }
}
