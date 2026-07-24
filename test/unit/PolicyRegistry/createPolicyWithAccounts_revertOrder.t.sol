// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `createPolicyWithAccounts`.
///
/// @notice **Canonical order:**
///         1. ZERO-ADMIN (`admin == address(0)`) → `ZeroAddress`
///         2. INCOMPATIBLE-TYPE (`policyType` is a composite gate) → `IncompatiblePolicyType`
///         3. BATCH-SIZE (`accounts.length > MAX_BATCH_SIZE`) → `BatchSizeTooLarge`
///
///         Walks from all conditions broken to success, fixing one per step.
contract PolicyRegistryCreatePolicyWithAccountsRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_createPolicyWithAccounts_revertOrder(address caller, address admin_, uint8 typeIdx, uint8 overflow)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory tooMany = _makeAccounts(n);
        address[] memory valid = new address[](0);

        // 1. ZERO-ADMIN: admin==address(0) AND composite type AND batch oversized → ZeroAddress fires first.
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        policyRegistry.createPolicyWithAccounts(address(0), _creatableCompositeType(typeIdx), tooMany);

        // Fix: use a non-zero admin.

        // 2. INCOMPATIBLE-TYPE: valid admin, but a composite gate AND batch oversized →
        //    IncompatiblePolicyType fires before the batch-size check.
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.createPolicyWithAccounts(admin_, _creatableCompositeType(typeIdx), tooMany);

        // Fix: use a simple policy type.

        // 3. BATCH-SIZE: valid admin and simple type, but accounts.length > MAX_BATCH_SIZE → BatchSizeTooLarge.
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        policyRegistry.createPolicyWithAccounts(admin_, pt, tooMany);

        // Fix: use an empty accounts array.

        // Success
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, pt, valid);
    }
}
