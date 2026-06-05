// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `transfer`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(TRANSFER)` modifier) → `ContractPaused`
///         2. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         3. ZERO-SENDER (`from == address(0)`) → `InvalidSender`
///         4. SENDER-POLICY (`_transfer` body) → `PolicyForbids(SENDER, ...)`
///         5. RECEIVER-POLICY (`_transfer` body) → `PolicyForbids(RECEIVER, ...)`
///         6. BALANCE (`_transfer` body) → `InsufficientBalance`
///
///         The public `transfer(to, amount)` entry sets `from = msg.sender`, so
///         pairs involving ZERO-SENDER require pranking `address(0)`. C(6, 2) = 15 pairs.
contract B20TransferRevertOrderTest is B20Test {
    // --- Pairs where PAUSE wins (PAUSE is canonical first) ---

    function test_transfer_revertOrder_pause_beats_zeroReceiver(address from, uint256 amount) public {
        _assumeValidActor(from);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(address(0), amount);
    }

    function test_transfer_revertOrder_pause_beats_zeroSender(address to, uint256 amount) public {
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(to, amount);
    }

    // --- Pairs where ZERO-RECEIVER wins (PAUSE not violated) ---

    function test_transfer_revertOrder_zeroReceiver_beats_zeroSender(uint256 amount) public {
        // Both `to` and `from` are address(0) — receiver check fires first.
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function test_transfer_revertOrder_zeroReceiver_beats_senderPolicy(address from, uint256 amount) public {
        _assumeValidActor(from);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function test_transfer_revertOrder_zeroReceiver_beats_receiverPolicy(address from, uint256 amount) public {
        _assumeValidActor(from);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function test_transfer_revertOrder_zeroReceiver_beats_balance(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 1, type(uint128).max);
        // `from` has zero balance → balance check WOULD fail if zero-receiver didn't fire first.

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    // --- Pairs where ZERO-SENDER wins (PAUSE not violated; requires pranking address(0)) ---

    function test_transfer_revertOrder_zeroSender_beats_senderPolicy(address to, uint256 amount) public {
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transfer(to, amount);
    }

    function test_transfer_revertOrder_zeroSender_beats_receiverPolicy(address to, uint256 amount) public {
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transfer(to, amount);
    }

    function test_transfer_revertOrder_zeroSender_beats_balance(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transfer(to, amount);
    }

    // --- Pairs where PAUSE wins ---

    function test_transfer_revertOrder_pause_beats_senderPolicy(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(to, amount);
    }

    function test_transfer_revertOrder_pause_beats_receiverPolicy(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _pause(IB20.PausableFeature.TRANSFER);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(to, amount);
    }

    function test_transfer_revertOrder_pause_beats_balance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transfer(to, amount);
    }

    // --- Pairs where SENDER-POLICY wins ---

    function test_transfer_revertOrder_senderPolicy_beats_receiverPolicy(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transfer(to, amount);
    }

    function test_transfer_revertOrder_senderPolicy_beats_balance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transfer(to, amount);
    }

    // --- Pair where RECEIVER-POLICY wins ---

    function test_transfer_revertOrder_receiverPolicy_beats_balance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_RECEIVER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transfer(to, amount);
    }
}
