// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20TransferFromWithMemoTest is B20Test {
    /// @notice Verifies transferFromWithMemo inherits all transferFrom guards
    /// @dev Reuse-of-guards invariant; concrete guard tests live in transferFrom.t.sol.
    ///      We use InsufficientAllowance as the representative guard.
    function test_transferFromWithMemo_revert_inheritsTransferFromGuards(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint256).max);
        // No approval set.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies transferFromWithMemo performs the same balance and allowance updates as transferFrom
    /// @dev Accounting and spend-tracking unchanged from transferFrom
    function test_transferFromWithMemo_success_movesBalanceAndDecreasesAllowance(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        amount = bound(amount, 1, type(uint128).max);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.balanceOf(from), 0, "from must be debited");
        assertEq(token.balanceOf(to), amount, "to must be credited");
        assertEq(token.allowance(from, caller), 0, "allowance must be consumed");
    }

    /// @notice Verifies transferFromWithMemo emits Transfer then Memo, in that order
    /// @dev Memo is the second log; canonical Memo test for the transferFrom path
    function test_transferFromWithMemo_success_emitsTransferThenMemo(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.expectEmit(true, false, false, false, address(token));
        emit IB20.Memo(memo);
        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies transferFromWithMemo returns true on success
    /// @dev Matches transferFrom's return-value contract
    function test_transferFromWithMemo_success_returnsTrue(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        assertTrue(token.transferFromWithMemo(from, to, amount, memo), "transferFromWithMemo must return true");
    }
}
