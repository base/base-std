// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20TransferWithMemoTest is B20Test {
    /// @notice Verifies transferWithMemo applies the same pause / policy / balance checks as transfer
    /// @dev Reuse-of-guards invariant; concrete guard tests live in transfer.t.sol.
    ///      We use TRANSFER pause as the representative guard — if the same _transfer path runs,
    ///      pause must fire identically.
    function test_transferWithMemo_revert_inheritsTransferGuards(address from, address to, uint256 amount, bytes32 memo)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferWithMemo(to, amount, memo);
    }

    /// @notice Verifies transferWithMemo performs the same balance movement as transfer
    /// @dev Same accounting effect as transfer; the memo does not alter accounting.
    ///      Paired slot assertions confirm both balance slots reflect the move.
    function test_transferWithMemo_success_movesBalance(address from, address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.transferWithMemo(to, amount, memo);

        assertEq(token.balanceOf(from), 0, "from must be fully debited");
        assertEq(token.balanceOf(to), amount, "to must be fully credited");
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
    }

    /// @notice Verifies transferWithMemo emits Transfer then Memo, in that order
    /// @dev Memo is the second log; canonical Memo emission test for the transfer path
    function test_transferWithMemo_success_emitsTransferThenMemo(address from, address to, uint256 amount, bytes32 memo)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.expectEmit(true, true, false, false, address(token));
        emit IB20.Memo(from, memo);
        vm.prank(from);
        token.transferWithMemo(to, amount, memo);
    }

    /// @notice Verifies transferWithMemo returns true on success
    /// @dev Matches transfer's return-value contract
    function test_transferWithMemo_success_returnsTrue(address from, address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        assertTrue(token.transferWithMemo(to, amount, memo), "transferWithMemo must return true");
    }
}
