// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20TransferWithMemoTest is B20Test {
    /// @notice Verifies transferWithMemo applies the same pause / policy / balance checks as transfer
    /// @dev Reuse-of-guards invariant; concrete guard tests live in transfer.t.sol.
    ///      We use TRANSFER pause as the representative guard — if the same _transfer path runs,
    ///      pause must fire identically.
    function test_transferWithMemo_revert_inheritsTransferGuards(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferWithMemo(to, amount, memo);
    }

    /// @notice Verifies transferWithMemo performs the same balance movement as transfer
    /// @dev Same accounting effect as transfer; the memo does not alter accounting
    function test_transferWithMemo_success_movesBalance(address from, address to, uint256 amount, bytes32 memo)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        vm.prank(from);
        token.transferWithMemo(to, amount, memo);

        assertEq(token.balanceOf(from), 0, "from must be fully debited");
        assertEq(token.balanceOf(to), amount, "to must be fully credited");
    }

    /// @notice Verifies transferWithMemo emits Transfer then Memo, in that order
    /// @dev Memo is the second log; canonical Memo emission test for the transfer path
    function test_transferWithMemo_success_emitsTransferThenMemo(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);

        _mint(from, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.expectEmit(true, false, false, false, address(token));
        emit IB20.Memo(memo);
        vm.prank(from);
        token.transferWithMemo(to, amount, memo);
    }

    /// @notice Verifies transferWithMemo returns true on success
    /// @dev Matches transfer's return-value contract
    function test_transferWithMemo_success_returnsTrue(address from, address to, uint256 amount, bytes32 memo)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);

        _mint(from, amount);
        vm.prank(from);
        assertTrue(token.transferWithMemo(to, amount, memo), "transferWithMemo must return true");
    }
}
