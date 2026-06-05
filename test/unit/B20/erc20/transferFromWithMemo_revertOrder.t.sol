// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Sequential check-order test for `transferFromWithMemo`.
///
/// @notice `transferFromWithMemo` carries the same preconditions as
///         `transferFrom`; the memo parameter adds no new revert conditions.
///
///         **Canonical order (Solidity reference, when `msg.sender != from`):**
///         1. PAUSE (`whenNotPaused(TRANSFER)` modifier) → `ContractPaused`
///         2. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         3. ZERO-SENDER (`from == address(0)`) → `InvalidSender`
///         4. ALLOWANCE (`_consumeAllowance`) → `InsufficientAllowance`
///         5. EXECUTOR-POLICY (`isAuthorized(executorPolicyId, msg.sender)`)
///            → `PolicyForbids(EXECUTOR, ...)`
///         6. SENDER-POLICY (first `_transfer` body check, representative)
///            → `PolicyForbids(SENDER, ...)`
///
///         The single test below activates all conditions simultaneously,
///         then fixes them one at a time in canonical order, asserting that
///         the next-priority revert fires at each step.
contract B20TransferFromWithMemoRevertOrderTest is B20Test {
    function test_transferFromWithMemo_revertOrder(
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
        amount = bound(amount, 1, type(uint128).max);

        // Activate all conditions: TRANSFER paused, from=address(0) and to=address(0)
        // as parameters, no allowance, executor policy blocks, sender policy blocks.
        _pause(IB20.PausableFeature.TRANSFER);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // 1. PAUSE fires first (all other violations also active).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFromWithMemo(address(0), address(0), amount, memo);
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.TRANSFER));

        // 2. ZERO-RECEIVER fires (pause cleared; from=address(0), to=address(0), no allowance,
        //    policies block).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transferFromWithMemo(address(0), address(0), amount, memo);

        // 3. ZERO-SENDER fires (pause+zero-receiver cleared; from=address(0), to=valid).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transferFromWithMemo(address(0), to, amount, memo);

        // 4. ALLOWANCE fires (pause+zero-addr cleared; from=valid, to=valid, no allowance,
        //    executor and sender policies still block).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFromWithMemo(from, to, amount, memo);
        vm.prank(from);
        token.approve(caller, amount);

        // 5. EXECUTOR-POLICY fires (all earlier cleared; executor policy blocks,
        //    sender policy also blocks).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_EXECUTOR_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFromWithMemo(from, to, amount, memo);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        // 6. SENDER-POLICY fires (all earlier cleared; sender policy still blocks,
        //    from has no balance — sender policy fires first).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFromWithMemo(from, to, amount, memo);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        _mint(from, amount);

        // Success — all conditions satisfied.
        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);
    }
}
