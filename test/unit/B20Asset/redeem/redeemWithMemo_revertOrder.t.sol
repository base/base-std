// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Asset} from "src/interfaces/IB20Asset.sol";

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

/// @title Sequential revert-order test for `redeemWithMemo` (asset variant).
///
/// @notice **Canonical order (Solidity reference `_redeemBurn`, shared with `redeem`):**
///         1. PAUSE (`_isPaused(REDEEM)`) → `ContractPaused`
///         2. POLICY (`isAuthorized(REDEEMSenderPolicyId, msg.sender)`) → `PolicyForbids`
///         3. BELOW-MIN (`shares == 0 || shares < minimum`) → `BelowMinimumRedeemable`
///         4. BALANCE (`fromBalance < amount` in `_burnRaw`) → `InsufficientBalance`
///
///         A single test activates all four conditions at once and fixes them from
///         highest to lowest priority, asserting each revert in turn then completing
///         a successful call once all conditions are resolved.
contract B20AssetRedeemWithMemoRevertOrderTest is B20AssetTest {
    /// @dev Unpauses a single feature via the `unpauser` actor, lazily granting
    ///      `UNPAUSE_ROLE` on first call. Mirrors the inherited `_pause` helper.
    function _unpause(IB20.PausableFeature feature) private {
        if (!token.hasRole(B20Constants.UNPAUSE_ROLE, unpauser)) _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(feature));
    }

    function test_redeemWithMemo_revertOrder(uint256 amount, uint256 minimum, bytes32 memo) public {
        amount = bound(amount, 1, type(uint64).max);
        minimum = bound(minimum, amount + 1, type(uint256).max);

        // Setup: activate ALL revert conditions simultaneously.
        //   REDEEM is paused, the sender policy blocks all callers,
        //   minimumRedeemable > amount (so shares == amount < minimum with the
        //   default 1:1 WAD ratio), and alice has zero balance.
        _pause(IB20.PausableFeature.REDEEM);
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _updateMinimumRedeemable(minimum);
        // alice balance is zero by default.

        // 1. PAUSE fires first.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.REDEEM));
        security().redeemWithMemo(amount, memo);

        // Fix: unpause REDEEM.
        _unpause(IB20.PausableFeature.REDEEM);

        // 2. POLICY fires next (pause fixed).
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, security().REDEEM_SENDER_POLICY(), PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        security().redeemWithMemo(amount, memo);

        // Fix: allow alice through the redeem-sender policy.
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        // 3. BELOW-MIN fires next (pause and policy fixed).
        //    With the default 1:1 WAD ratio shares == amount, and amount < minimum.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.BelowMinimumRedeemable.selector, amount, minimum));
        security().redeemWithMemo(amount, memo);

        // Fix: clear the minimum floor so shares == amount satisfies the check.
        _updateMinimumRedeemable(0);

        // 4. BALANCE fires next (pause, policy, and minimum fixed).
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, alice, 0, amount));
        security().redeemWithMemo(amount, memo);

        // Fix: give alice exactly enough balance to cover the redemption.
        _mint(alice, amount);

        // Success: all conditions resolved.
        vm.prank(alice);
        security().redeemWithMemo(amount, memo);
    }
}
