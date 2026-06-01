// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

import {B20Constants} from "src/lib/B20Constants.sol";

/// @title Differential check-order tests for `updateMinimumRedeemable`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(DEFAULT_ADMIN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         Single revert condition — no ordering pairs. One test pins the guard itself.
contract B20AssetUpdateMinimumRedeemableRevertOrderTest is B20AssetTest {
    function test_updateMinimumRedeemable_revertOrder_unauthorized(address caller, uint256 newMinimum) public {
        vm.assume(caller != admin);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        security().updateMinimumRedeemable(newMinimum);
    }
}
