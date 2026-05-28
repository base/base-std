// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `transferFrom`.
///
/// @notice `transferFrom` adds two preconditions on top of `_transfer`'s checks
///         (already pinned by `transfer_revertOrder.t.sol`):
///
///         **Canonical order (Solidity reference, when `msg.sender != from`):**
///         1. ALLOWANCE (`_consumeAllowance`) → `InsufficientAllowance`
///         2. EXECUTOR-POLICY (`isAuthorized(executorPolicyId, msg.sender)`) → `PolicyForbids(EXECUTOR, ...)`
///         3..N. (all `_transfer` body checks — see `transfer_revertOrder.t.sol`)
///
///         These tests pin the two new preconditions against each other and
///         against a representative `_transfer` body check (ZERO-RECEIVER) to
///         prove they fire before `_transfer` is entered.
contract B20TransferFromRevertOrderTest is B20Test {
    /// @notice ALLOWANCE beats EXECUTOR-POLICY.
    function test_transferFrom_revertOrder_allowance_beats_executorPolicy(
        address caller,
        address from,
        address to,
        uint256 amount
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);
        // Allowance is 0 (less than amount) AND executor policy blocks caller.
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice ALLOWANCE beats anything in `_transfer` (representative: ZERO-RECEIVER).
    function test_transferFrom_revertOrder_allowance_beats_transferBody(address caller, address from, uint256 amount)
        public
    {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);
        // Allowance is 0 AND `to` is address(0).

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFrom(from, address(0), amount);
    }

    /// @notice EXECUTOR-POLICY beats anything in `_transfer` (representative: ZERO-RECEIVER).
    /// @dev Allowance is set high enough to pass the allowance check, so the executor-policy
    ///      check is reached next, and it fires before `_transfer` is entered.
    function test_transferFrom_revertOrder_executorPolicy_beats_transferBody(
        address caller,
        address from,
        uint256 amount
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);
        // Sufficient allowance, executor policy blocks caller, `to` is address(0).
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
        token.transferFrom(from, address(0), amount);
    }
}
