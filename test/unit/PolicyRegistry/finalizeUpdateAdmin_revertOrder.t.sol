// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `finalizeUpdateAdmin`.
///
/// @notice **Canonical order:**
///         1. POLICY-NOT-FOUND (`policies[policyId] == 0`) → `PolicyNotFound`
///         2. NO-PENDING-ADMIN (`pendingAdmins[policyId] == address(0)`) → `NoPendingAdmin`
///         3. UNAUTHORIZED (`pendingAdmins[policyId] != msg.sender`) → `Unauthorized`
///
///         Walks from all conditions broken to success, fixing one per step.
contract PolicyRegistryFinalizeUpdateAdminRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_finalizeUpdateAdmin_revertOrder() public {
        // ghostId is a well-formed policyId that has never been created.
        uint64 ghostId = _wellFormedUncreatedPolicyId(type(uint64).max);

        // 1. POLICY-NOT-FOUND: policyId has never been created AND no pending admin is
        //    staged (NoPendingAdmin and Unauthorized would also apply once a policy exists).
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.finalizeUpdateAdmin(ghostId);

        // Fix: create an allowlist policy with alice as admin.
        uint64 policyId = policyRegistry.createPolicy(alice, IPolicyRegistry.PolicyType.ALLOWLIST);

        // 2. NO-PENDING-ADMIN: policy exists but no pending admin has been staged.
        //    (Unauthorized would also fire if NoPendingAdmin were absent, since
        //    pendingAdmins[policyId] == address(0) != attacker.)
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.NoPendingAdmin.selector);
        policyRegistry.finalizeUpdateAdmin(policyId);

        // Fix: stage bob as the pending admin.
        vm.prank(alice);
        policyRegistry.stageUpdateAdmin(policyId, bob);

        // 3. UNAUTHORIZED: bob is the staged pending admin, but attacker is calling.
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.finalizeUpdateAdmin(policyId);

        // Fix: call as bob (the staged pending admin).

        // Success
        vm.prank(bob);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }
}
