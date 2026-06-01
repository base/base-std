// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

/// @title Differential check-order tests for `updateShareRatio`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(OPERATOR_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         Single revert condition — no ordering pairs. One test pins the guard itself.
contract B20AssetUpdateShareRatioRevertOrderTest is B20AssetTest {
    function test_updateShareRatio_revertOrder_unauthorized(address caller, uint256 newRatio) public {
        vm.assume(caller != admin);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, security().OPERATOR_ROLE()
            )
        );
        security().updateShareRatio(newRatio);
    }
}
