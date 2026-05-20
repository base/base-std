// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryFinalizeUpdateAdminTest is PolicyRegistryTest {
    /// @notice Verifies finalizeUpdateAdmin reverts when no admin transfer is in flight
    /// @dev Pending-slot precondition; checks NoPendingAdmin() error
    function test_finalizeUpdateAdmin_revert_noPendingAdmin(address caller) public {
        _assumeValidCaller(caller);
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectRevert(IPolicyRegistry.NoPendingAdmin.selector);
        vm.prank(caller);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    /// @notice Verifies finalizeUpdateAdmin reverts for callers other than the staged pending admin
    /// @dev Access control: only the pending admin can claim; checks Unauthorized() error
    function test_finalizeUpdateAdmin_revert_unauthorized(address pending, address caller) public {
        _assumeValidCaller(caller);
        vm.assume(pending != address(0));
        vm.assume(caller != pending);
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, pending);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    /// @notice Verifies finalizeUpdateAdmin reverts for an unknown policy id
    /// @dev Built-ins and unknown ids are not administrable; checks PolicyNotFound() error
    function test_finalizeUpdateAdmin_revert_policyNotFound(address caller, uint64 policyId) public {
        _assumeValidCaller(caller);
        vm.assume(policyId > 1);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    /// @notice Verifies finalizeUpdateAdmin promotes the pending admin to current admin
    /// @dev policyAdmin returns the previously-staged address after this call
    function test_finalizeUpdateAdmin_success_promotesPending(address currentAdmin, address newAdmin) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        vm.prank(newAdmin);
        policyRegistry.finalizeUpdateAdmin(policyId);
        assertEq(policyRegistry.policyAdmin(policyId), newAdmin);
    }

    /// @notice Verifies finalizeUpdateAdmin clears the pending slot
    /// @dev pendingPolicyAdmin returns address(0) after the transfer completes
    function test_finalizeUpdateAdmin_success_clearsPending(address currentAdmin, address newAdmin) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        vm.prank(newAdmin);
        policyRegistry.finalizeUpdateAdmin(policyId);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies finalizeUpdateAdmin emits PolicyAdminUpdated with previousAdmin and newAdmin
    /// @dev Canonical PolicyAdminUpdated event test; other emission paths (create / renounce) are
    ///      tested in their own files because their args differ (previousAdmin = 0 / newAdmin = 0)
    function test_finalizeUpdateAdmin_success_emitsPolicyAdminUpdated(address currentAdmin, address newAdmin) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(policyId, currentAdmin, newAdmin);
        vm.prank(newAdmin);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }
}
