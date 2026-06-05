// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `updateBlocklist`.
///
/// @notice **Canonical order:**
///         1. POLICY-NOT-FOUND (`policies[policyId] == 0`) → `PolicyNotFound`
///         2. INCOMPATIBLE-TYPE (`_typeOf(policyId) != BLOCKLIST`) → `IncompatiblePolicyType`
///         3. UNAUTHORIZED (`_decodeAdmin(packed) != msg.sender`) → `Unauthorized`
///         4. BATCH-SIZE (inside `_batchSetMembers`) → `BatchSizeTooLarge`
///
///         Walks from all conditions broken to success, fixing one per step.
///         Mirror of `updateAllowlist_revertOrder.t.sol` with ALLOWLIST and BLOCKLIST roles swapped.
contract PolicyRegistryUpdateBlocklistRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_updateBlocklist_revertOrder(uint8 overflow) public {
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory tooMany = _makeAccounts(n);
        address[] memory empty = new address[](0);
        // ghostId is a well-formed policyId that has never been created.
        uint64 ghostId = _wellFormedUncreatedPolicyId(type(uint64).max);

        // 1. POLICY-NOT-FOUND: policyId has never been created AND all later conditions
        //    would also apply (wrong type, unauthorized caller, oversized batch).
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateBlocklist(ghostId, true, tooMany);

        // Fix: create an ALLOWLIST policy with alice as admin (exists, but wrong type for updateBlocklist).
        uint64 allowlistId = _createAllowlist(admin, alice);

        // 2. INCOMPATIBLE-TYPE: policy exists as ALLOWLIST; updateBlocklist requires BLOCKLIST.
        //    (Unauthorized and BatchSizeTooLarge would also apply.)
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.updateBlocklist(allowlistId, true, tooMany);

        // Fix: create a BLOCKLIST policy with alice as admin.
        uint64 policyId = _createBlocklist(admin, alice);

        // 3. UNAUTHORIZED: policy is BLOCKLIST but attacker is not the policy admin (alice).
        //    (BatchSizeTooLarge would also apply.)
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.updateBlocklist(policyId, true, tooMany);

        // Fix: call as alice (the policy admin).

        // 4. BATCH-SIZE: alice is the admin, but accounts.length > MAX_BATCH_SIZE.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        policyRegistry.updateBlocklist(policyId, true, tooMany);

        // Fix: use an empty accounts array.

        // Success
        vm.prank(alice);
        policyRegistry.updateBlocklist(policyId, true, empty);
    }
}
