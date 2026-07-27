// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {IScaledUIAmount} from "base-std/interfaces/IScaledUIAmount.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @notice A matured-but-uncancelled pending must be folded into the current multiplier before any
///         set/cancel overwrites slot 4, so a scheduled change is never silently lost.
contract B20AssetMaterializeTest is B20AssetTest {
    bytes32 internal constant CANCELLED_SIG = keccak256("MultiplierUpdateCancelled(uint256,uint256)");

    /// @notice Verifies scheduling over a *matured* pending folds it into the current multiplier
    function test_setUIMultiplier_success_materializesMaturedPending() public {
        uint256 first = 2e18;
        uint256 firstEffectiveAt = block.timestamp + 1 days;
        _setUIMultiplier(first, firstEffectiveAt);
        vm.warp(firstEffectiveAt + 1);
        assertEq(asset().uiMultiplier(), first, "precondition: first schedule has matured");

        uint256 second = 3e18;
        uint256 secondEffectiveAt = block.timestamp + 1 days;
        _grantOperator();
        vm.expectEmit(false, false, false, true, address(token));
        emit IScaledUIAmount.UIMultiplierUpdated(first, second, secondEffectiveAt);
        vm.prank(operator);
        asset().setUIMultiplier(second, secondEffectiveAt);

        // The matured `first` was folded into slot 1 and is still effective before `second` matures.
        assertEq(asset().uiMultiplier(), first, "matured pending must be folded into current, not lost");
        assertEq(
            uint256(vm.load(address(token), MockB20AssetStorage.multiplierSlot())),
            first,
            "slot 1 must hold the folded matured multiplier"
        );
        assertEq(asset().newUIMultiplier(), second, "new pending must be recorded");
        assertEq(asset().effectiveAt(), secondEffectiveAt, "new effectiveAt must be recorded");

        vm.warp(secondEffectiveAt);
        assertEq(asset().uiMultiplier(), second, "second schedule flips in on maturity");
    }

    /// @notice Verifies updateMultiplier clears a *live* pending and emits the cancellation
    function test_updateMultiplier_success_clearsLivePending() public {
        uint256 pendingMultiplier = 2e18;
        uint256 effectiveAt = block.timestamp + 1 days;
        _setUIMultiplier(pendingMultiplier, effectiveAt);

        uint256 instant = 5e18;
        uint256 old = asset().uiMultiplier();
        _grantOperator();
        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Asset.MultiplierUpdateCancelled(pendingMultiplier, effectiveAt);
        vm.expectEmit(false, false, false, true, address(token));
        emit IScaledUIAmount.UIMultiplierUpdated(old, instant, block.timestamp);
        vm.prank(operator);
        asset().updateMultiplier(instant);

        assertEq(asset().uiMultiplier(), instant, "instant update must take effect immediately");
        assertEq(uint256(vm.load(address(token), MockB20AssetStorage.pendingSlot())), 0, "pending must be cleared");
        assertEq(asset().effectiveAt(), 0, "effectiveAt must reset to 0");
    }

    /// @notice Verifies updateMultiplier clears a *matured* pending WITHOUT a cancellation event
    /// @dev A matured pending already took effect, so it folds into `oldMultiplier` and is cleared
    ///      silently — `MultiplierUpdateCancelled` fires only for a live pending.
    function test_updateMultiplier_success_clearsMaturedPendingNoCancelEvent() public {
        uint256 matured = 2e18;
        uint256 effectiveAt = block.timestamp + 1 days;
        _setUIMultiplier(matured, effectiveAt);
        vm.warp(effectiveAt + 1);

        uint256 instant = 5e18;
        _grantOperator();
        vm.recordLogs();
        vm.prank(operator);
        asset().updateMultiplier(instant);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _firstLogIndex(logs, CANCELLED_SIG),
            -1,
            "no MultiplierUpdateCancelled for a matured (already-effective) pending"
        );
        assertEq(asset().uiMultiplier(), instant, "instant update must take effect immediately");
        assertEq(
            uint256(vm.load(address(token), MockB20AssetStorage.pendingSlot())), 0, "matured pending must be cleared"
        );
    }
}
