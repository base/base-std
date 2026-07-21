// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20AssetCancelScheduledMultiplierTest is B20AssetTest {
    /// @notice Verifies cancel clears the live pending and restores the no-pending state
    /// @dev Paired slot assertion: slot 4 is zeroed. `effectiveAt()` resets to 0 and
    ///      `newUIMultiplier() == uiMultiplier()` (no-live-pending invariant).
    function test_cancelScheduledMultiplier_success_clearsPending(uint256 newMultiplier, uint256 effectiveAt) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        effectiveAt = bound(effectiveAt, block.timestamp + 1, type(uint64).max);
        _setUIMultiplier(newMultiplier, effectiveAt);

        _cancelScheduledMultiplier();

        assertEq(
            uint256(vm.load(address(token), MockB20AssetStorage.pendingSlot())), 0, "slot 4 must be cleared on cancel"
        );
        assertEq(asset().effectiveAt(), 0, "effectiveAt must reset to 0 after cancel");
        assertEq(asset().newUIMultiplier(), asset().uiMultiplier(), "no-live-pending: newUIMultiplier == uiMultiplier");
    }

    /// @notice Verifies cancel emits MultiplierUpdateCancelled(cancelledMultiplier, cancelledEffectiveAt)
    function test_cancelScheduledMultiplier_success_emitsEvent(uint256 newMultiplier, uint256 effectiveAt) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        effectiveAt = bound(effectiveAt, block.timestamp + 1, type(uint64).max);
        _setUIMultiplier(newMultiplier, effectiveAt);

        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Asset.MultiplierUpdateCancelled(newMultiplier, effectiveAt);
        vm.prank(operator);
        asset().cancelScheduledMultiplier();
    }

    /// @notice Verifies cancel does not disturb the current effective multiplier
    function test_cancelScheduledMultiplier_success_leavesCurrentUntouched(uint256 current) public {
        current = bound(current, 1, type(uint128).max);
        _updateMultiplier(current);
        _setUIMultiplier(2e18, block.timestamp + 1 days);

        _cancelScheduledMultiplier();

        assertEq(asset().multiplier(), current, "cancel must leave the current multiplier unchanged");
    }

    /// @notice Verifies cancel reverts when the caller lacks OPERATOR_ROLE
    function test_cancelScheduledMultiplier_revert_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);
        _setUIMultiplier(2e18, block.timestamp + 1 days);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE));
        asset().cancelScheduledMultiplier();
    }

    /// @notice Verifies cancel reverts when nothing is scheduled
    function test_cancelScheduledMultiplier_revert_noPending() public {
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(IB20Asset.NoScheduledMultiplier.selector);
        asset().cancelScheduledMultiplier();
    }

    /// @notice Verifies cancel reverts once the pending has matured
    function test_cancelScheduledMultiplier_revert_matured(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        uint256 effectiveAt = block.timestamp + 1 days;
        _setUIMultiplier(newMultiplier, effectiveAt);
        vm.warp(effectiveAt);

        vm.prank(operator);
        vm.expectRevert(IB20Asset.NoScheduledMultiplier.selector);
        asset().cancelScheduledMultiplier();
    }
}
