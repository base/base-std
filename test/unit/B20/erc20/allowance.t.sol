// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";

contract B20AllowanceTest is B20Test {
    /// @notice Verifies allowance returns zero for any unconfigured (owner, spender) pair
    /// @dev Default state across the address space
    function test_allowance_success_zeroByDefault(address owner, address spender) public view {
        assertEq(token.allowance(owner, spender), 0, "untouched allowance must be zero");
    }

    /// @notice Verifies allowance reflects the value set via approve
    /// @dev Approval readback; canonical approve test lives in approve.t.sol
    function test_allowance_success_reflectsApprove(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        // Spender may be address(0)? approve reverts on InvalidSpender(0), so filter.
        vm.assume(spender != address(0));

        vm.prank(owner);
        token.approve(spender, amount);
        assertEq(token.allowance(owner, spender), amount, "allowance must reflect approve");
    }

    /// @notice Verifies allowance decreases after a successful transferFrom
    /// @dev Spend-tracking readback; canonical transferFrom test lives in transferFrom.t.sol
    function test_allowance_success_decreasesAfterTransferFrom(
        address owner,
        address spender,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        _assumeValidActor(owner);
        _assumeValidActor(spender);
        _assumeValidActor(to);
        vm.assume(owner != to);
        // transferFrom only consumes allowance when msg.sender != from (see MockB20._transferFrom);
        // owner == spender skips the consumption path, so filter it out.
        vm.assume(owner != spender);
        // allowanceAmount > 0 keeps the allowance setup meaningful; spendAmount includes 0
        // so the assertion (allowance decreases by spendAmount) is exercised across the full
        // valid input domain, including the no-op zero-spend case.
        allowanceAmount = bound(allowanceAmount, 1, type(uint128).max);
        spendAmount = bound(spendAmount, 0, allowanceAmount);

        _mint(owner, spendAmount);
        vm.prank(owner);
        token.approve(spender, allowanceAmount);

        vm.prank(spender);
        token.transferFrom(owner, to, spendAmount);

        assertEq(
            token.allowance(owner, spender), allowanceAmount - spendAmount, "allowance must decrease by spent amount"
        );
    }
}
