// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

/// @title Sequential revert-order test for `updateMultiplier`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(OPERATOR_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. INVALID-MULTIPLIER (`newMultiplier == 0`) → `InvalidMultiplier`
///
///         Walks from all conditions broken to success, fixing one per step.
contract B20AssetUpdateMultiplierRevertOrderTest is B20AssetTest {
    function test_updateMultiplier_revertOrder(address caller) public {
        // Exclude precompiles (which can distort msg.sender) and admin (needed
        // internally by _grantRole to approve the role grant).
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        // Resolve the role constant before setting the prank; an external view
        // call inside abi.encodeWithSelector would otherwise consume vm.prank
        // before the state-changing call, sending it as address(this) instead.
        bytes32 operatorRole = asset().OPERATOR_ROLE();

        // 1. ROLE fires: caller lacks OPERATOR_ROLE AND multiplier is zero.
        //    The role modifier runs before the body's zero-multiplier check.
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, operatorRole));
        asset().updateMultiplier(0);

        // Fix: grant OPERATOR_ROLE to caller.
        _grantRole(operatorRole, caller);

        // 2. INVALID-MULTIPLIER fires: caller now holds the role, but multiplier is still zero.
        vm.prank(caller);
        vm.expectRevert(IB20Asset.InvalidMultiplier.selector);
        asset().updateMultiplier(0);

        // Fix: pass a non-zero multiplier.

        // Success: all conditions resolved.
        vm.prank(caller);
        asset().updateMultiplier(1e18);
    }
}
