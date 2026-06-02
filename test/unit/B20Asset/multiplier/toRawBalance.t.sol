// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

contract B20AssetToRawBalanceTest is B20AssetTest {
    /// @notice Verifies toRawBalance is the identity on a fresh token (WAD multiplier)
    /// @dev Default multiplier is WAD, so scaledBalance * WAD / WAD == scaledBalance for every input.
    function test_toRawBalance_success_identityOnWadDefault(uint256 scaledBalance) public view {
        scaledBalance = bound(scaledBalance, 0, type(uint256).max / asset().WAD_PRECISION());
        assertEq(asset().toRawBalance(scaledBalance), scaledBalance, "default multiplier must produce identity");
    }

    /// @notice Verifies toRawBalance inverts the stored multiplier after an update
    /// @dev Property: toRawBalance(scaledBalance) == scaledBalance * WAD / multiplier. Fuzz both
    ///      inputs over the range that avoids the intermediate-product overflow.
    function test_toRawBalance_success_invertsByStoredMultiplier(uint256 scaledBalance, uint256 newMultiplier) public {
        scaledBalance = bound(scaledBalance, 0, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(
            asset().toRawBalance(scaledBalance),
            (scaledBalance * asset().WAD_PRECISION()) / newMultiplier,
            "toRawBalance must apply scaledBalance * WAD / multiplier"
        );
    }

    /// @notice Verifies toRawBalance of zero scaled balance is zero regardless of the multiplier
    /// @dev Degenerate input edge: any multiplier divided into zero is zero.
    function test_toRawBalance_success_zeroScaledBalance(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint256).max);
        _updateMultiplier(newMultiplier);
        assertEq(asset().toRawBalance(0), 0, "zero scaled balance must produce zero raw balance");
    }

    /// @notice Verifies toRawBalance applies the WAD fallback when the stored multiplier is explicitly zero
    /// @dev A stored `multiplier` of zero is documented to resolve as `WAD_PRECISION` on the read
    ///      surface, both pre-write (fresh slot) and post-explicit-zero-write. Tests the latter at
    ///      the derived-function level so a refactor that reads the slot directly here would fail.
    ///      See test_multiplier_success_zeroRestoresWadFallback for the base-level fallback assertion.
    function test_toRawBalance_success_explicitZeroMultiplierFallsBackToWad(uint256 scaledBalance) public {
        scaledBalance = bound(scaledBalance, 0, type(uint128).max);
        _updateMultiplier(5e18); // seed a non-zero value first
        _updateMultiplier(0); // then explicitly clear back to zero
        assertEq(
            asset().toRawBalance(scaledBalance),
            scaledBalance,
            "stored zero multiplier must produce identity (WAD fallback)"
        );
    }

    /// @notice Verifies the round-trip toRawBalance(toScaledBalance(x)) == x at the WAD default
    /// @dev With multiplier == WAD, both directions collapse to the identity, so the round-trip
    ///      is exact.
    function test_toRawBalance_success_roundTripExactOnWadDefault(uint256 rawBalance) public view {
        rawBalance = bound(rawBalance, 0, type(uint256).max / asset().WAD_PRECISION());
        uint256 scaled = asset().toScaledBalance(rawBalance);
        assertEq(asset().toRawBalance(scaled), rawBalance, "round-trip must be exact at WAD multiplier");
    }

    /// @notice Verifies the round-trip toRawBalance(toScaledBalance(x)) <= x for arbitrary multipliers
    /// @dev Both legs floor-divide. The forward leg loses up to one ULP and the reverse leg loses
    ///      up to one more, so the round-trip can return a value strictly less than `x`. Bound the
    ///      gap precisely: the post-trip value lies in `[x - 1 - WAD/multiplier, x]` for non-zero
    ///      multipliers <= WAD, and is upper-bounded by `x` everywhere. The conservative invariant
    ///      asserted here is `toRawBalance(toScaledBalance(x)) <= x`.
    function test_toRawBalance_success_roundTripFloors(uint256 rawBalance, uint256 newMultiplier) public {
        // Bound the multiplier strictly below WAD to actually exercise the floor — at multipliers
        // >= WAD the forward leg loses nothing, so the round-trip is exact and uninteresting.
        rawBalance = bound(rawBalance, 0, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, asset().WAD_PRECISION() - 1);
        _updateMultiplier(newMultiplier);
        uint256 scaled = asset().toScaledBalance(rawBalance);
        uint256 roundTripped = asset().toRawBalance(scaled);
        assertLe(roundTripped, rawBalance, "round-trip must not exceed input (floors at each step)");
    }
}
