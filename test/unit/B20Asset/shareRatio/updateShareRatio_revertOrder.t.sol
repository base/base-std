// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

/// @title Sequential revert-order test for `updateShareRatio`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(OPERATOR_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         A single test verifies the guard fires for an unauthorized caller and then
///         confirms the call succeeds once the role is granted.
contract B20AssetUpdateShareRatioRevertOrderTest is B20AssetTest {
    function test_updateShareRatio_revertOrder(address caller, uint256 newRatio) public {
        // Exclude precompiles (which can distort msg.sender) and admin (needed
        // internally by _grantRole to approve the role grant).
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        // Resolve the role identifier before setting the prank; an external view
        // call inside abi.encodeWithSelector would otherwise consume vm.prank
        // before the state-changing call, sending it as address(this) instead.
        bytes32 operatorRole = security().OPERATOR_ROLE();

        // 1. ROLE fires.
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, operatorRole));
        security().updateShareRatio(newRatio);

        // Fix: grant OPERATOR_ROLE to caller.
        _grantRole(operatorRole, caller);

        // Success: all conditions resolved.
        vm.prank(caller);
        security().updateShareRatio(newRatio);
    }
}
