// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @title Sequential revert-order test for `createPolicy`.
///
/// @notice **Canonical order:**
///         1. ZERO-ADMIN (`admin == address(0)`) → `ZeroAddress`
///         2. COUNTER-OVERFLOW (nextCounter == type(uint56).max) → `Panic(0x11)`
///
///         Walks from the first failing condition to success.
///
/// @dev    Mock-only: this test forces `nextCounter` with `vm.store`, which cannot
///         write to native precompile addresses under `LIVE_PRECOMPILES=true`.
contract PolicyRegistryCreatePolicyRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_createPolicy_revertOrder(address caller, address admin_, uint8 typeIdx) public {
        vm.skip(livePrecompiles);

        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);

        // 1. ZERO-ADMIN: admin == address(0) → ZeroAddress
        vm.store(
            address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot(), bytes32(uint256(type(uint56).max))
        );
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        policyRegistry.createPolicy(address(0), pt);

        // Fix: use a non-zero admin.

        // 2. COUNTER-OVERFLOW: nextCounter == type(uint56).max → Panic(0x11)
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        policyRegistry.createPolicy(admin_, pt);

        // Fix: reset counter to a valid value.
        vm.store(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot(), bytes32(uint256(2)));

        // Success
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }
}
