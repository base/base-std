// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPendingPolicyAdminTest is PolicyRegistryTest {
    /// @notice Verifies pendingPolicyAdmin returns address(0) before any transfer is staged
    /// @dev Default state for a freshly-created policy
    function test_pendingPolicyAdmin_success_defaultZero() public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns the address most recently staged
    /// @dev Read-after-write for stageUpdateAdmin
    function test_pendingPolicyAdmin_success_returnsStaged(address newAdmin) public {
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), newAdmin);
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) after finalizeUpdateAdmin
    /// @dev Pending slot is cleared once the transfer completes
    function test_pendingPolicyAdmin_success_zeroAfterFinalize(address newAdmin) public {
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        vm.prank(newAdmin);
        policyRegistry.finalizeUpdateAdmin(policyId);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) after renounceAdmin
    /// @dev In-flight transfers are invalidated as a side effect of renouncement
    function test_pendingPolicyAdmin_success_zeroAfterRenounce(address pending) public {
        vm.assume(pending != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, pending);
        vm.prank(admin);
        policyRegistry.renounceAdmin(policyId);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) for built-in policies
    /// @dev Built-ins have no admin and therefore no pending admin
    function test_pendingPolicyAdmin_success_zeroForBuiltins() public view {
        assertEq(policyRegistry.pendingPolicyAdmin(0), address(0));
        assertEq(policyRegistry.pendingPolicyAdmin(1), address(0));
    }
}
