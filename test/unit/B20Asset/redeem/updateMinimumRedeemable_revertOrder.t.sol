// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

/// @title Sequential revert-order test for `updateMinimumRedeemable`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(DEFAULT_ADMIN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         A single test verifies the guard fires for an unauthorized caller and then
///         confirms the call succeeds once the role is granted.
contract B20AssetUpdateMinimumRedeemableRevertOrderTest is B20AssetTest {
    function test_updateMinimumRedeemable_revertOrder(address caller, uint256 newMinimum) public {
        // Exclude precompiles (which can distort msg.sender) and admin (who already
        // holds DEFAULT_ADMIN_ROLE, which would make the initial call succeed).
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        // 1. ROLE fires.
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        security().updateMinimumRedeemable(newMinimum);

        // Fix: grant DEFAULT_ADMIN_ROLE to caller.
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, caller);

        // Success: all conditions resolved.
        vm.prank(caller);
        security().updateMinimumRedeemable(newMinimum);
    }
}
