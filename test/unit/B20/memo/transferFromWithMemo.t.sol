// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

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
    /// @dev Accounting and spend-tracking unchanged from transferFrom.
    ///      Paired slot assertions confirm both balance slots and the
    ///      allowance slot reflect the move and consumption.
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
        // Include amount = 0: the balance/allowance invariants must hold across the full
        // valid input domain, including the no-op zero-transfer case.
        amount = bound(amount, 0, type(uint128).max);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.balanceOf(from), 0, "from must be debited");
        assertEq(token.balanceOf(to), amount, "to must be credited");
        assertEq(token.allowance(from, caller), 0, "allowance must be consumed");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            0,
            "balances[from] slot must reflect the debit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            amount,
            "balances[to] slot must reflect the credit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, caller))),
            0,
            "allowances[from][caller] slot must reflect the consumption"
        );
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
        vm.expectEmit(true, true, false, false, address(token));
        emit IB20.Memo(caller, memo);
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

    // ============================================================
    //              REGRESSION: SELF-CALLER ALLOWANCE
    // ============================================================
    //
    // Mirrors the transferFrom regression: msg.sender == from MUST still
    // consume allowance. See transferFrom.t.sol for the canonical
    // regression discussion.

    /// @notice Verifies transferFromWithMemo reverts InsufficientAllowance when caller == from and no self-approval exists
    /// @dev Regression: inherits the corrected allowance-consumption invariant from transferFrom.
    function test_transferFromWithMemo_revert_selfCaller_insufficientAllowance(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, from, 0, amount));
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies transferFromWithMemo decreases self-allowance by the spent amount when caller == from
    /// @dev Regression: spend-tracking parity with transferFrom on the self-caller path.
    function test_transferFromWithMemo_success_selfCaller_decreasesAllowance(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, type(uint128).max);

        _mint(from, amount);
        vm.prank(from);
        token.approve(from, amount);

        vm.prank(from);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.allowance(from, from), 0, "self-allowance must be consumed");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, from))),
            0,
            "allowances[from][from] slot must reflect the consumption"
        );
        assertEq(token.balanceOf(to), amount, "to must receive the transferred amount");
    }
}
