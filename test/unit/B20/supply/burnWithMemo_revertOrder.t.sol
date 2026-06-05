// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Sequential check-order test for `burnWithMemo` (self-burn with memo).
///
/// @notice `burnWithMemo` carries the same access-control and balance
///         preconditions as `burn`; the memo parameter adds no new revert
///         conditions.
///
///         **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(BURN)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(BURN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. BALANCE (`fromBalance < amount` in `_burnRaw`) → `InsufficientBalance`
///
///         The single test below activates all three violations simultaneously,
///         then fixes them one at a time in canonical order, asserting that the
///         next-priority revert fires at each step.
contract B20BurnWithMemoRevertOrderTest is B20Test {
    function test_burnWithMemo_revertOrder(address caller, uint256 amount, bytes32 memo) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        amount = bound(amount, 1, type(uint128).max);

        // Activate all three violations: BURN paused, caller has no BURN_ROLE, zero balance.
        _pause(IB20.PausableFeature.BURN);

        // 1. PAUSE fires first (role and balance also violated).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        token.burnWithMemo(amount, memo);
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.BURN));

        // 2. ROLE fires (pause cleared; no BURN_ROLE, zero balance).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_ROLE)
        );
        token.burnWithMemo(amount, memo);
        _grantRole(B20Constants.BURN_ROLE, caller);

        // 3. BALANCE fires (pause+role cleared; caller has zero balance, amount>0).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, caller, 0, amount));
        token.burnWithMemo(amount, memo);
        _mint(caller, amount);

        // Success — all conditions satisfied.
        vm.prank(caller);
        token.burnWithMemo(amount, memo);
    }
}
