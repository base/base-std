// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetNewUIMultiplierTest is B20AssetTest {
    /// @notice Verifies a live pending exposes its target and effective time
    /// @dev While `effectiveAt > block.timestamp`: `newUIMultiplier()` is the scheduled target,
    ///      `effectiveAt()` is the schedule time, and `uiMultiplier()` still reads the old value.
    function test_newUIMultiplier_success_reportsLivePending(uint256 newMultiplier, uint256 effectiveAt) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        vm.assume(newMultiplier != asset().WAD_PRECISION());
        effectiveAt = bound(effectiveAt, block.timestamp + 1, type(uint64).max);

        uint256 oldMultiplier = asset().uiMultiplier();
        _setUIMultiplier(newMultiplier, effectiveAt);

        assertEq(asset().newUIMultiplier(), newMultiplier, "newUIMultiplier must report the live pending target");
        assertEq(asset().effectiveAt(), effectiveAt, "effectiveAt must report the schedule time");
        assertEq(asset().uiMultiplier(), oldMultiplier, "uiMultiplier must still read the pre-schedule value");
    }

    /// @notice Verifies a matured-but-uncancelled pending mirrors uiMultiplier and keeps its past effectiveAt
    /// @dev Once matured, `effectiveAt <= block.timestamp` reads as "no live pending":
    ///      `newUIMultiplier() == uiMultiplier()` (both the matured value). The stored `effectiveAt`
    ///      retains its (now past) value until the next set/cancel materializes it
    function test_newUIMultiplier_success_maturedMirrorsUiMultiplier(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        uint256 effectiveAt = block.timestamp + 5 days;
        _setUIMultiplier(newMultiplier, effectiveAt);
        vm.warp(effectiveAt + 1);

        assertEq(asset().newUIMultiplier(), asset().uiMultiplier(), "matured: newUIMultiplier == uiMultiplier");
        assertEq(asset().newUIMultiplier(), newMultiplier, "matured: both read the matured value");
        assertEq(asset().effectiveAt(), effectiveAt, "matured effectiveAt is retained (past) until re-set");
    }
}
