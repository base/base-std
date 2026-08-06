// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {IScaledUIAmount} from "base-std/interfaces/IERC8056.sol";

contract B20AssetUpdateUIMultiplierTest is B20AssetTest {
    /// @notice Verifies updateUIMultiplier emits UIMultiplierUpdated(old, new, effectiveAt)
    function test_updateUIMultiplier_success_emitsEvent(uint256 newMultiplier, uint256 effectiveAt) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        effectiveAt = bound(effectiveAt, block.timestamp + 1, type(uint64).max);
        _grantOperator();

        uint256 oldMultiplier = asset().multiplier();
        vm.expectEmit(false, false, false, true, address(token));
        emit IScaledUIAmount.UIMultiplierUpdated(oldMultiplier, newMultiplier, effectiveAt);
        vm.prank(operator);
        asset().updateUIMultiplier(newMultiplier, effectiveAt);
    }

    /// @notice Verifies the effective multiplier flips lazily exactly at `effectiveAt`
    function test_updateUIMultiplier_success_lazyFlipAtBoundary(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        vm.assume(newMultiplier != asset().WAD_PRECISION());
        uint256 effectiveAt = block.timestamp + 7 days;
        uint256 oldMultiplier = asset().multiplier();

        _updateUIMultiplier(newMultiplier, effectiveAt);

        vm.warp(effectiveAt - 1);
        assertEq(asset().uiMultiplier(), oldMultiplier, "T-1: must still read the old multiplier");

        vm.warp(effectiveAt);
        assertEq(asset().uiMultiplier(), newMultiplier, "T: must read the new multiplier");

        vm.warp(effectiveAt + 1);
        assertEq(asset().uiMultiplier(), newMultiplier, "T+1: must still read the new multiplier");
    }

    /// @notice Verifies updateUIMultiplier reverts when the caller lacks OPERATOR_ROLE
    function test_updateUIMultiplier_revert_unauthorized(address caller, uint256 newMultiplier) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE));
        asset().updateUIMultiplier(newMultiplier, block.timestamp + 1);
    }

    /// @notice Verifies updateUIMultiplier reverts on a zero multiplier
    function test_updateUIMultiplier_revert_zeroMultiplier() public {
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(IB20Asset.InvalidMultiplier.selector);
        asset().updateUIMultiplier(0, block.timestamp + 1);
    }

    /// @notice Verifies updateUIMultiplier reverts above the uint128 ceiling
    function test_updateUIMultiplier_revert_aboveUint128Ceiling(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, uint256(type(uint128).max) + 1, type(uint256).max);
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(IB20Asset.InvalidMultiplier.selector);
        asset().updateUIMultiplier(newMultiplier, block.timestamp + 1);
    }

    /// @notice Verifies updateUIMultiplier reverts when effectiveAt is not in the future
    function test_updateUIMultiplier_revert_effectiveAtInPast(uint256 effectiveAt) public {
        effectiveAt = bound(effectiveAt, 0, block.timestamp);
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.EffectiveAtInPast.selector, effectiveAt));
        asset().updateUIMultiplier(2e18, effectiveAt);
    }

    /// @notice Verifies updateUIMultiplier reverts when effectiveAt exceeds the uint64 storage width
    function test_updateUIMultiplier_revert_effectiveAtTooFar(uint256 effectiveAt) public {
        effectiveAt = bound(effectiveAt, uint256(type(uint64).max) + 1, type(uint256).max);
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.EffectiveAtTooFar.selector, effectiveAt));
        asset().updateUIMultiplier(2e18, effectiveAt);
    }

    /// @notice Verifies updateUIMultiplier reverts when a live pending update already exists
    function test_updateUIMultiplier_revert_pendingUpdateExists(uint256 firstEffectiveAt, uint256 secondEffectiveAt)
        public
    {
        firstEffectiveAt = bound(firstEffectiveAt, block.timestamp + 1, type(uint64).max);
        secondEffectiveAt = bound(secondEffectiveAt, block.timestamp + 1, type(uint64).max);
        _updateUIMultiplier(2e18, firstEffectiveAt);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.UIMultiplierUpdateExists.selector, firstEffectiveAt));
        asset().updateUIMultiplier(3e18, secondEffectiveAt);
    }
}
