// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `stageUpdateAdmin`.
///
/// @notice **Canonical order:**
///         1. POLICY-NOT-FOUND (`policies[policyId] == 0`) → `PolicyNotFound`
///         2. UNAUTHORIZED (`_decodeAdmin(packed) != msg.sender`) → `Unauthorized`
///
///         Walks from all conditions broken to success, fixing one per step.
contract PolicyRegistryStageUpdateAdminRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_stageUpdateAdmin_revertOrder(address newAdmin) public {
        // ghostId is a well-formed policyId that has never been created.
        uint64 ghostId = _wellFormedUncreatedPolicyId(type(uint64).max);

        // 1. POLICY-NOT-FOUND: policyId has never been created AND attacker is not the
        //    policy admin (Unauthorized would also apply if the policy existed).
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.stageUpdateAdmin(ghostId, newAdmin);

        // Fix: create an allowlist policy with alice as admin.
        uint64 policyId = policyRegistry.createPolicy(alice, IPolicyRegistry.PolicyType.ALLOWLIST);

        // 2. UNAUTHORIZED: attacker is not the policy admin (alice).
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);

        // Fix: call as alice (the policy admin).

        // Success
        vm.prank(alice);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
    }
}
