// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

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

    /// @notice Verifies transfer reverts when sender is not authorized under TRANSFER_SENDER_POLICY
    /// @dev Policy guard for the from-side; checks PolicyForbids(TRANSFER_SENDER_POLICY, policyId) error
    function test_transfer_revert_senderPolicyForbids(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer reverts when recipient is not authorized under TRANSFER_RECEIVER_POLICY
    /// @dev Policy guard for the to-side; checks PolicyForbids(TRANSFER_RECEIVER_POLICY, policyId) error
    function test_transfer_revert_receiverPolicyForbids(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID));
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

    /// @notice Verifies transfer reverts when called by the zero address
    /// @dev Defense-in-depth check inside _transfer: from == address(0) reverts InvalidSender
    ///      before any pause / policy / balance checks. For the public `transfer` path
    ///      from = msg.sender, so reaching this branch requires pranking address(0)
    ///      (filtered out of our normal fuzz tests by _assumeValidActor).
    function test_transfer_revert_zeroSender(address to, uint256 amount) public {
        _assumeValidActor(to);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transfer(to, amount);
    }

    /// @notice Verifies transfer debits the sender balance by amount
    /// @dev Accounting half: balanceOf(from) decreases by exactly amount.
    ///      Paired slot assertion: `balances[from]` slot reflects the
    ///      debit so the Rust precompile impl can be cross-validated
    ///      against the same storage layout.
    function test_transfer_success_debitsSender(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        uint256 before = token.balanceOf(from);

        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(from), before - amount, "from must be debited by amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            before - amount,
            "balances[from] slot must reflect the debit"
        );
    }

    /// @notice Verifies transfer credits the receiver balance by amount
    /// @dev Accounting half: balanceOf(to) increases by exactly amount.
    ///      Paired slot assertion: `balances[to]` slot reflects the credit.
    function test_transfer_success_creditsReceiver(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);

        _mint(from, amount);
        uint256 before = token.balanceOf(to);

        vm.prank(from);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), before + amount, "to must be credited by amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            before + amount,
            "balances[to] slot must reflect the credit"
        );
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
