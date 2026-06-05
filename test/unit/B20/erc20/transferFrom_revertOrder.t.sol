// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `transferFrom`.
///
/// @notice `transferFrom` layers two body-level preconditions
///         (ALLOWANCE and EXECUTOR-POLICY) on top of `_transfer`'s
///         policy / balance checks. The PAUSE / ZERO-RECEIVER /
///         ZERO-SENDER guards run before the allowance / executor-policy
///         work in the entrypoint body.
///
///         **Canonical order (Solidity reference, when
///         `msg.sender != from`):**
///         1. PAUSE (`whenNotPaused(TRANSFER)` modifier) → `ContractPaused`
///         2. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         3. ZERO-SENDER (`from == address(0)`) → `InvalidSender`
///         4. ALLOWANCE (`_consumeAllowance`) → `InsufficientAllowance`
///         5. EXECUTOR-POLICY (`isAuthorized(executorPolicyId, msg.sender)`)
///            → `PolicyForbids(EXECUTOR, ...)`
///         6..N. All `_transfer` body checks — see `transfer_revertOrder.t.sol`
///               (SENDER-POLICY → RECEIVER-POLICY → BALANCE).
///
///         The full pair matrix between body-level ALLOWANCE/EXECUTOR-POLICY
///         and the PAUSE/ZERO-RECEIVER/ZERO-SENDER guards is pinned below;
///         one test against a representative `_transfer` body check
///         (SENDER-POLICY) proves ALLOWANCE and EXECUTOR-POLICY both
///         fire before `_transfer` is entered.
contract B20TransferFromRevertOrderTest is B20Test {
    // --- Pairs where PAUSE wins (PAUSE is canonical first) ---

    /// @notice PAUSE beats ALLOWANCE.
    function test_transferFrom_revertOrder_pause_beats_allowance(
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
        _pause(IB20.PausableFeature.TRANSFER);
        // No allowance set → ALLOWANCE would fire if PAUSE didn't.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    /// @notice PAUSE beats EXECUTOR-POLICY.
    function test_transferFrom_revertOrder_pause_beats_executorPolicy(
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
        _pause(IB20.PausableFeature.TRANSFER);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    // --- Pairs where ZERO-RECEIVER wins (PAUSE not violated) ---

    /// @notice ZERO-RECEIVER beats ALLOWANCE.
    /// @dev Zero-receiver check fires before the allowance check.
    function test_transferFrom_revertOrder_zeroReceiver_beats_allowance(address caller, address from, uint256 amount)
        public
    {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);
        // No allowance AND `to == address(0)`.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transferFrom(from, address(0), amount);
    }

    /// @notice ZERO-RECEIVER beats EXECUTOR-POLICY.
    function test_transferFrom_revertOrder_zeroReceiver_beats_executorPolicy(
        address caller,
        address from,
        uint256 amount
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint128).max);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transferFrom(from, address(0), amount);
    }

    // --- Pairs where ZERO-SENDER wins (PAUSE + ZERO-RECEIVER not violated) ---

    /// @notice ZERO-SENDER beats ALLOWANCE.
    /// @dev Zero-sender check fires before the allowance check.
    function test_transferFrom_revertOrder_zeroSender_beats_allowance(address caller, address to, uint256 amount)
        public
    {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transferFrom(address(0), to, amount);
    }

    /// @notice ZERO-SENDER beats EXECUTOR-POLICY.
    function test_transferFrom_revertOrder_zeroSender_beats_executorPolicy(address caller, address to, uint256 amount)
        public
    {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint128).max);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSender.selector, address(0)));
        token.transferFrom(address(0), to, amount);
    }

    // --- Pairs where ALLOWANCE wins (PAUSE + input not violated) ---

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

    /// @notice ALLOWANCE beats anything in `_transfer` (representative: SENDER-POLICY).
    /// @dev `_transfer`'s body is policy + balance + effects (input validation
    ///      lives on the entrypoint); SENDER-POLICY is the first body check
    ///      inside `_transfer`.
    function test_transferFrom_revertOrder_allowance_beats_transferBody(
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
        // Allowance is 0 AND sender policy blocks `from`.
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFrom(from, to, amount);
    }

    // --- Pair where EXECUTOR-POLICY wins (everything earlier satisfied) ---

    /// @notice EXECUTOR-POLICY beats anything in `_transfer` (representative: SENDER-POLICY).
    /// @dev Allowance is set high enough to pass the allowance check, so the
    ///      executor-policy check runs next and fires before `_transfer` is
    ///      entered.
    function test_transferFrom_revertOrder_executorPolicy_beats_transferBody(
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
        // Sufficient allowance, executor policy blocks caller, sender policy also blocks `from`.
        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

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
}
