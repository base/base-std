// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20TransferFromTest is B20Test {
    /// @notice Verifies transferFrom reverts when the TRANSFER feature is paused
    /// @dev Pause guard fires in the inner _transfer, after allowance consumption.
    ///      To reach it we need a non-zero allowance so the consumeAllowance step
    ///      doesn't revert first.
    function test_transferFrom_revert_whenTransferPaused(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from); // skip the consume-allowance bypass when caller == from
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(from);
        token.approve(caller, amount);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when caller is not authorized under TRANSFER_EXECUTOR_POLICY
    /// @dev Executor-side policy guard fires after allowance consumption and before _transfer.
    function test_transferFrom_revert_executorPolicyForbids(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_EXECUTOR_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when from is not authorized under TRANSFER_SENDER_POLICY
    /// @dev Sender-side policy guard fires inside _transfer.
    function test_transferFrom_revert_senderPolicyForbids(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when to is not authorized under TRANSFER_RECEIVER_POLICY
    /// @dev Receiver-side policy guard fires inside _transfer.
    function test_transferFrom_revert_receiverPolicyForbids(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_RECEIVER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when caller's allowance is insufficient
    /// @dev Allowance precondition fires first when caller != from; checks InsufficientAllowance
    function test_transferFrom_revert_insufficientAllowance(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint256).max);
        // No approval set; allowance is 0; any nonzero amount exceeds it.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when from's balance is insufficient
    /// @dev Balance precondition fires inside _transfer, after allowance consumption.
    function test_transferFrom_revert_insufficientBalance(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);
        // from has zero balance, but allowance is set high enough to clear the allowance gate.

        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom debits from balance and credits to balance
    /// @dev Accounting invariant for the transferFrom path.
    ///      Paired slot assertions verify both `balances[from]` and
    ///      `balances[to]` slots reflect the move.
    function test_transferFrom_success_movesBalance(address caller, address from, address to, uint256 amount) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(from), 0, "from must be fully debited");
        assertEq(token.balanceOf(to), amount, "to must be fully credited");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            0,
            "balances[from] slot must reflect the full debit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            amount,
            "balances[to] slot must reflect the full credit"
        );
    }

    /// @notice Verifies transferFrom decreases caller allowance by exactly amount
    /// @dev Spend-tracking; non-infinite allowances decrement by the transferred amount.
    ///      Paired slot assertion: `allowances[from][caller]` slot
    ///      reflects the consumed amount.
    function test_transferFrom_success_decreasesAllowance(
        address caller,
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        allowanceAmount = bound(allowanceAmount, 1, type(uint128).max);
        // Cap below type(uint256).max so we exercise the consume path (not the infinite-allowance bypass).
        vm.assume(allowanceAmount != type(uint256).max);
        spendAmount = bound(spendAmount, 1, allowanceAmount);

        _mint(from, spendAmount);
        vm.prank(from);
        token.approve(caller, allowanceAmount);

        vm.prank(caller);
        token.transferFrom(from, to, spendAmount);

        assertEq(
            token.allowance(from, caller), allowanceAmount - spendAmount, "allowance must decrease by spent amount"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, caller))),
            allowanceAmount - spendAmount,
            "allowances[from][caller] slot must reflect the consumed amount"
        );
    }

    /// @notice Verifies transferFrom leaves an infinite allowance unchanged
    /// @dev Convention: type(uint256).max allowance is treated as unlimited and not decremented.
    ///      Paired slot assertion confirms the slot still holds uint256.max.
    function test_transferFrom_success_infiniteAllowanceUnchanged(
        address caller,
        address from,
        address to,
        uint256 amount
    ) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        amount = bound(amount, 1, type(uint128).max);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, type(uint256).max);

        vm.prank(caller);
        token.transferFrom(from, to, amount);

        assertEq(token.allowance(from, caller), type(uint256).max, "infinite allowance must be preserved");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, caller))),
            type(uint256).max,
            "allowances[from][caller] slot must still hold the infinite sentinel"
        );
    }

    /// @notice Verifies transferFrom emits Transfer(from, to, amount)
    /// @dev Event integrity for the transferFrom path; canonical Transfer test lives in transfer.t.sol
    function test_transferFrom_success_emitsTransfer(address caller, address from, address to, uint256 amount) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.prank(caller);
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom returns true on success
    /// @dev ERC-20 return-value contract
    function test_transferFrom_success_returnsTrue(address caller, address from, address to, uint256 amount) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        assertTrue(token.transferFrom(from, to, amount), "transferFrom must return true");
    }
}
