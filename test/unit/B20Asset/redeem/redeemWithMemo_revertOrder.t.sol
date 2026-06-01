// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Asset} from "src/interfaces/IB20Asset.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `redeemWithMemo` (asset variant).
///
/// @notice **Canonical order (Solidity reference `_redeemBurn`, shared with `redeem`):**
///         1. PAUSE (`_isPaused(REDEEM)`) → `ContractPaused`
///         2. POLICY (`isAuthorized(REDEEMSenderPolicyId, msg.sender)`) → `PolicyForbids`
///         3. BELOW-MIN (`shares == 0 || shares < minimum`) → `BelowMinimumRedeemable`
///         4. BALANCE (`fromBalance < amount` in `_burnRaw`) → `InsufficientBalance`
///
///         `redeemWithMemo` delegates to `_redeemBurn` identically to `redeem`;
///         only the subsequent `Memo` event emission differs. The ordering is
///         therefore the same as `redeem_revertOrder.t.sol`.
///
///         C(4, 2) = 6 pairs.
contract B20AssetRedeemWithMemoRevertOrderTest is B20AssetTest {
    // --- Pairs where PAUSE wins ---

    function test_redeemWithMemo_revertOrder_pause_beats_policy(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, type(uint128).max);
        _pause(IB20.PausableFeature.REDEEM);
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.REDEEM));
        security().redeemWithMemo(amount, memo);
    }

    function test_redeemWithMemo_revertOrder_pause_beats_belowMinimum(uint256 amount, uint256 minimum, bytes32 memo)
        public
    {
        amount = bound(amount, 1, type(uint64).max);
        minimum = bound(minimum, amount + 1, type(uint256).max);
        _pause(IB20.PausableFeature.REDEEM);
        _updateMinimumRedeemable(minimum);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.REDEEM));
        security().redeemWithMemo(amount, memo);
    }

    function test_redeemWithMemo_revertOrder_pause_beats_balance(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, type(uint128).max);
        _pause(IB20.PausableFeature.REDEEM);
        // alice has zero balance.

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.REDEEM));
        security().redeemWithMemo(amount, memo);
    }

    // --- Pairs where POLICY wins ---

    function test_redeemWithMemo_revertOrder_policy_beats_belowMinimum(
        uint256 amount,
        uint256 minimum,
        bytes32 memo
    ) public {
        amount = bound(amount, 1, type(uint64).max);
        minimum = bound(minimum, amount + 1, type(uint256).max);
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _updateMinimumRedeemable(minimum);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, security().REDEEM_SENDER_POLICY(), PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        security().redeemWithMemo(amount, memo);
    }

    function test_redeemWithMemo_revertOrder_policy_beats_balance(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, type(uint128).max);
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        // alice has zero balance.

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, security().REDEEM_SENDER_POLICY(), PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        security().redeemWithMemo(amount, memo);
    }

    // --- Pair where BELOW-MIN wins ---

    function test_redeemWithMemo_revertOrder_belowMinimum_beats_balance(
        uint256 amount,
        uint256 minimum,
        bytes32 memo
    ) public {
        amount = bound(amount, 1, type(uint64).max);
        minimum = bound(minimum, amount + 1, type(uint256).max);
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        _updateMinimumRedeemable(minimum);
        // alice has zero balance → BALANCE would fire if BELOW-MIN didn't.
        // Default WAD ratio: shares = amount * WAD / WAD = amount. amount < minimum → BelowMinimumRedeemable.

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.BelowMinimumRedeemable.selector, amount, minimum));
        security().redeemWithMemo(amount, memo);
    }
}
