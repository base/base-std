// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPolicyAdminTest is PolicyRegistryTest {
    /// @notice Verifies policyAdmin reverts PolicyNotFound for a well-formed but uncreated id
    /// @dev Lookup guard for non-existent ids; uses a well-formed id so the malformed
    ///      check passes and the storage-lookup miss fires.
    function test_policyAdmin_revert_policyNotFound(uint64 seed) public {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.policyAdmin(policyId);
    }

    /// @notice Verifies policyAdmin reverts MalformedPolicyId for any id whose top byte
    ///         is outside the PolicyType enum range.
    /// @dev Encoding invariant on the registry surface.
    function test_policyAdmin_revert_malformedPolicyId(uint64 seed) public {
        uint64 policyId = _malformedPolicyId(seed);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.MalformedPolicyId.selector, policyId));
        policyRegistry.policyAdmin(policyId);
    }

    /// @notice Verifies policyAdmin returns address(0) for built-in policies
    /// @dev Built-ins have no admin; both id 0 and id 1 return zero
    function test_policyAdmin_success_zeroForBuiltins() public view {
        assertEq(policyRegistry.policyAdmin(0), address(0));
        assertEq(policyRegistry.policyAdmin(1), address(0));
    }

    /// @notice Verifies policyAdmin returns the admin nominated at creation time
    /// @dev Initial-admin readback
    function test_policyAdmin_success_returnsAssigned(address admin_) public {
        vm.assume(admin_ != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertEq(policyRegistry.policyAdmin(policyId), admin_);
    }

    /// @notice Verifies policyAdmin returns address(0) after renounceAdmin
    /// @dev Post-renounce: admin slot is permanently cleared
    function test_policyAdmin_success_zeroAfterRenounce(address admin_) public {
        vm.assume(admin_ != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin_);
        policyRegistry.renounceAdmin(policyId);
        assertEq(policyRegistry.policyAdmin(policyId), address(0));
    }
}
