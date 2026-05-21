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

    /// @notice policyExists returns false for a well-formed but uncreated id.
    /// @dev Uses a well-formed id (top byte in PolicyType range) so the malformed
    ///      check passes and the storage-lookup miss returns false.
    function test_policyExists_success_falseForUncreated(uint64 seed) public view {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        assertFalse(policyRegistry.policyExists(policyId));
    }

    /// @notice policyExists reverts MalformedPolicyId for any id whose top byte is
    ///         outside the PolicyType enum range.
    /// @dev Encoding invariant on the registry surface.
    function test_policyExists_revert_malformedPolicyId(uint64 seed) public {
        uint64 policyId = _malformedPolicyId(seed);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.MalformedPolicyId.selector, policyId));
        policyRegistry.policyExists(policyId);
    }

    function test_policyExists_success_trueAfterCreate(uint8 typeIdx) public {
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint64 policyId = policyRegistry.createPolicy(admin, pt);
        assertTrue(policyRegistry.policyExists(policyId));
    }
}
