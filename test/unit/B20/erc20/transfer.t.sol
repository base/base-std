// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20TransferTest is B20Test {
    /// @notice Verifies transfer reverts when the TRANSFER feature is paused
    /// @dev Pause guard fires before policy or balance checks; checks ContractPaused(TRANSFER) error
    function test_transfer_revert_whenTransferPaused(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when sender is not authorized under TRANSFER_SENDER
    /// @dev Policy guard for the from-side; checks PolicyForbids(TRANSFER_SENDER, policyId) error
    function test_transfer_revert_senderPolicyForbids(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(TRANSFER_SENDER, ALWAYS_REJECT);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, TRANSFER_SENDER, ALWAYS_REJECT));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when recipient is not authorized under TRANSFER_RECEIVER
    /// @dev Policy guard for the to-side; checks PolicyForbids(TRANSFER_RECEIVER, policyId) error
    function test_transfer_revert_receiverPolicyForbids(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(TRANSFER_RECEIVER, ALWAYS_REJECT);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, TRANSFER_RECEIVER, ALWAYS_REJECT));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when sender balance is insufficient
    /// @dev Balance precondition; checks InsufficientBalance(sender, balance, amount) error
    function test_transfer_revert_insufficientBalance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);
        // from has zero balance; any nonzero amount exceeds it.

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts for the zero recipient address
    /// @dev OZ ERC-6093 invariant; checks InvalidReceiver(address(0)) error
    function test_transfer_revert_zeroRecipient(address from, uint256 amount) public {
        _assumeValidActor(from);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    /// @notice Verifies transfer debits the sender balance by amount
    /// @dev Accounting half: balanceOf(from) decreases by exactly amount
    function test_transfer_success_debitsSender(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        uint256 before = token.balanceOf(from);

        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(from), before - amount, "from must be debited by amount");
    }

    /// @notice Verifies transfer credits the receiver balance by amount
    /// @dev Accounting half: balanceOf(to) increases by exactly amount
    function test_transfer_success_creditsReceiver(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        uint256 before = token.balanceOf(to);

        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), before + amount, "to must be credited by amount");
    }

    /// @notice Verifies transfer emits Transfer(from, to, amount)
    /// @dev Event integrity; canonical Transfer event test for the transfer path
    function test_transfer_success_emitsTransfer(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);

        _mint(from, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer returns true on success
    /// @dev ERC-20 return-value contract
    function test_transfer_success_returnsTrue(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);

        _mint(from, amount);

        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer must return true");
    }
}
