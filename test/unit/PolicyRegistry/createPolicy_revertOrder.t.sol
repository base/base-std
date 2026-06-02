// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `createPolicy`.
///
/// @notice **Canonical order:**
///         1. ZERO-ADMIN (`admin == address(0)`) → `ZeroAddress`
///
///         Single revert condition; walks from that condition to success.
contract PolicyRegistryCreatePolicyRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_createPolicy_revertOrder(address caller, address admin_, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);

        // 1. ZERO-ADMIN: admin == address(0) → ZeroAddress
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        policyRegistry.createPolicy(address(0), pt);

        // Fix: use a non-zero admin.

        // Success
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }
}
