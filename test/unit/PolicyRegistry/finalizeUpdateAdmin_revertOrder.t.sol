// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @title Differential check-order tests for `finalizeUpdateAdmin`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. POLICY-NOT-FOUND (`policies[policyId] == 0`) → `PolicyNotFound`
///         2. NO-PENDING-ADMIN (`pendingAdmins[policyId] == address(0)`) → `NoPendingAdmin`
///         3. UNAUTHORIZED (`pendingAdmins[policyId] != msg.sender`) → `Unauthorized`
///
///         C(3, 2) = 3 pairs.
contract PolicyRegistryFinalizeUpdateAdminRevertOrderTest is PolicyRegistryTest {
    // ---------------------------------------------------------------
    // Pairs where POLICY-NOT-FOUND wins
    // ---------------------------------------------------------------

    /// @notice POLICY-NOT-FOUND beats NO-PENDING-ADMIN.
    /// @dev policyId does not exist (packed == 0) AND no pending admin is staged.
    ///      PolicyNotFound fires before the pending-admin slot is read.
    function test_finalizeUpdateAdmin_revertOrder_policyNotFound_beats_noPendingAdmin(uint64 seed) public {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);

        // Both conditions apply independently:
        // - PolicyNotFound: policyId has never been created.
        // - NoPendingAdmin: pendingAdmins[policyId] == address(0) (zero storage).
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    /// @notice POLICY-NOT-FOUND beats UNAUTHORIZED.
    /// @dev policyId does not exist AND caller is not address(0), so the pending-admin
    ///      comparison (address(0) != caller) would trigger Unauthorized if reached.
    ///      PolicyNotFound fires before the pending-admin slot or caller comparison runs.
    function test_finalizeUpdateAdmin_revertOrder_policyNotFound_beats_unauthorized(address caller, uint64 seed)
        public
    {
        _assumeValidCaller(caller);
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);

        // Both conditions apply independently:
        // - PolicyNotFound: policyId has never been created (packed == 0).
        // - Unauthorized: pendingAdmins[policyId] == address(0) != caller.
        //   (NoPendingAdmin also applies; it would fire second if PolicyNotFound didn't.)
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    // ---------------------------------------------------------------
    // Pairs where NO-PENDING-ADMIN wins
    // ---------------------------------------------------------------

    /// @notice NO-PENDING-ADMIN beats UNAUTHORIZED.
    /// @dev Policy exists but has no pending admin staged. Caller is a non-zero address,
    ///      so `pendingAdmins[policyId] (== address(0)) != caller` would trigger
    ///      Unauthorized if the NoPendingAdmin guard were absent.
    function test_finalizeUpdateAdmin_revertOrder_noPendingAdmin_beats_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        // Create a policy; no stageUpdateAdmin call follows, so pending == address(0).
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);

        // Both conditions apply independently:
        // - NoPendingAdmin: pendingAdmins[policyId] == address(0).
        // - Unauthorized: address(0) != caller (caller is non-zero).
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.NoPendingAdmin.selector);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }
}
