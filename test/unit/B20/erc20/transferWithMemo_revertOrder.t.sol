// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Sequential check-order test for `transferWithMemo`.
///
/// @notice `transferWithMemo` carries the same preconditions as `transfer`;
///         the memo parameter adds no new revert conditions.
///
///         **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(TRANSFER)` modifier) → `ContractPaused`
///         2. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         3. ZERO-SENDER (`from == address(0)`) → `InvalidSender`
///         4. SENDER-POLICY (`_transfer` body) → `PolicyForbids(SENDER, ...)`
///         5. RECEIVER-POLICY (`_transfer` body) → `PolicyForbids(RECEIVER, ...)`
///         6. BALANCE (`_transfer` body) → `InsufficientBalance`
///
///         The public `transferWithMemo(to, amount, memo)` entry sets
///         `from = msg.sender`. The single test below activates all six
///         violations simultaneously, then fixes them one at a time in
///         canonical order, asserting that the next-priority revert fires
///         at each step.
contract B20TransferWithMemoRevertOrderTest is B20Test {
    function test_transferWithMemo_revertOrder(address from, address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);

        // Activate all six violations: TRANSFER paused, from=address(0) (via prank),
        // to=address(0), sender policy blocks, receiver policy blocks, from has zero balance.
        _pause(IB20.PausableFeature.TRANSFER);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // 1. PAUSE fires first (all other violations also active; pranking address(0) for ZERO-SENDER).
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferWithMemo(address(0), amount, memo);
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.TRANSFER));

        // 2. ZERO-RECEIVER fires (pause cleared; from=address(0), to=address(0),
        //    policies block, zero balance — receiver is checked before sender).
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transferWithMemo(address(0), amount, memo);

        // 3. ZERO-SENDER fires (pause+zero-receiver cleared; from=address(0), to=valid).
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transferWithMemo(to, amount, memo);

        // 4. SENDER-POLICY fires (all earlier cleared; sender policy blocks, receiver also blocks).
        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferWithMemo(to, amount, memo);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        // 5. RECEIVER-POLICY fires (all earlier cleared; receiver policy still blocks).
        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_RECEIVER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferWithMemo(to, amount, memo);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        // 6. BALANCE fires (all earlier cleared; from has zero balance, amount>0).
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.transferWithMemo(to, amount, memo);
        _mint(from, amount);

        // Success — all conditions satisfied.
        vm.prank(from);
        token.transferWithMemo(to, amount, memo);
    }
}
