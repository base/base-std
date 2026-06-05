// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `updateAllowlist`.
///
/// @notice **Canonical order:**
///         1. POLICY-NOT-FOUND (`policies[policyId] == 0`) → `PolicyNotFound`
///         2. INCOMPATIBLE-TYPE (`_typeOf(policyId) != ALLOWLIST`) → `IncompatiblePolicyType`
///         3. UNAUTHORIZED (`_decodeAdmin(packed) != msg.sender`) → `Unauthorized`
///         4. BATCH-SIZE (inside `_batchSetMembers`) → `BatchSizeTooLarge`
///
///         Walks from all conditions broken to success, fixing one per step.
contract PolicyRegistryUpdateAllowlistRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_updateAllowlist_revertOrder(uint8 overflow) public {
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory tooMany = _makeAccounts(n);
        address[] memory empty = new address[](0);
        // ghostId is a well-formed policyId that has never been created.
        uint64 ghostId = _wellFormedUncreatedPolicyId(type(uint64).max);

        // 1. POLICY-NOT-FOUND: policyId has never been created AND all later conditions
        //    would also apply (wrong type, unauthorized caller, oversized batch).
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateAllowlist(ghostId, true, tooMany);

        // Fix: create a BLOCKLIST policy with alice as admin (exists, but wrong type for updateAllowlist).
        uint64 blocklistId = _createBlocklist(admin, alice);

        // 2. INCOMPATIBLE-TYPE: policy exists as BLOCKLIST; updateAllowlist requires ALLOWLIST.
        //    (Unauthorized and BatchSizeTooLarge would also apply.)
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.updateAllowlist(blocklistId, true, tooMany);

        // Fix: create an ALLOWLIST policy with alice as admin.
        uint64 policyId = _createAllowlist(admin, alice);

        // 3. UNAUTHORIZED: policy is ALLOWLIST but attacker is not the policy admin (alice).
        //    (BatchSizeTooLarge would also apply.)
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.updateAllowlist(policyId, true, tooMany);

        // Fix: call as alice (the policy admin).

        // 4. BATCH-SIZE: alice is the admin, but accounts.length > MAX_BATCH_SIZE.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        policyRegistry.updateAllowlist(policyId, true, tooMany);

        // Fix: use an empty accounts array.

        // Success
        vm.prank(alice);
        policyRegistry.updateAllowlist(policyId, true, empty);
    }
}
