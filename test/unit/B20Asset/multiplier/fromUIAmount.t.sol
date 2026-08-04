// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20AssetFromUIAmountTest is B20AssetTest {
    /// @notice Verifies fromUIAmount is the identity on a fresh token (WAD multiplier)
    /// @dev Default multiplier is WAD, so uiAmount * WAD / WAD == uiAmount for every input.
    function test_fromUIAmount_success_identityOnWadDefault(uint256 uiAmount) public view {
        uiAmount = bound(uiAmount, 0, type(uint256).max / asset().WAD_PRECISION());
        assertEq(asset().fromUIAmount(uiAmount), uiAmount, "default multiplier must produce identity");
    }

    /// @notice Verifies fromUIAmount inverts the stored multiplier after an update
    /// @dev Property: fromUIAmount(uiAmount) == uiAmount * WAD / multiplier. Fuzz both
    ///      inputs over the range that avoids the intermediate-product overflow.
    function test_fromUIAmount_success_invertsByStoredMultiplier(uint256 uiAmount, uint256 newMultiplier) public {
        uiAmount = bound(uiAmount, 0, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(
            asset().fromUIAmount(uiAmount),
            (uiAmount * asset().WAD_PRECISION()) / newMultiplier,
            "fromUIAmount must apply uiAmount * WAD / multiplier"
        );
    }

    /// @notice Verifies fromUIAmount of zero UI amount is zero regardless of the multiplier
    /// @dev Degenerate input edge: any multiplier divided into zero is zero.
    function test_fromUIAmount_success_zeroUIAmount(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(asset().fromUIAmount(0), 0, "zero UI amount must produce zero raw amount");
    }

    /// @notice Verifies fromUIAmount applies the WAD fallback when the stored multiplier is zero
    /// @dev A stored `multiplier` of zero resolves as `WAD_PRECISION` on the read surface.
    ///      `updateUIMultiplier(0)` now reverts (InvalidMultiplier), so we zero the slot via
    ///      vm.store to isolate the read-path fallback from write-path validation.
    function test_fromUIAmount_success_explicitZeroMultiplierFallsBackToWad(uint256 uiAmount) public {
        uiAmount = bound(uiAmount, 0, type(uint128).max);
        _updateMultiplier(5e18); // seed a non-zero value first
        vm.store(address(token), MockB20AssetStorage.multiplierSlot(), bytes32(0)); // zero the slot directly
        assertEq(
            asset().fromUIAmount(uiAmount), uiAmount, "stored zero multiplier must produce identity (WAD fallback)"
        );
    }

    /// @notice Verifies the round-trip fromUIAmount(toUIAmount(x)) == x at the WAD default
    /// @dev With multiplier == WAD, both directions collapse to the identity, so the round-trip
    ///      is exact.
    function test_fromUIAmount_success_roundTripExactOnWadDefault(uint256 rawAmount) public view {
        rawAmount = bound(rawAmount, 0, type(uint256).max / asset().WAD_PRECISION());
        uint256 ui = asset().toUIAmount(rawAmount);
        assertEq(asset().fromUIAmount(ui), rawAmount, "round-trip must be exact at WAD multiplier");
    }

    /// @notice Verifies the round-trip fromUIAmount(toUIAmount(x)) <= x for arbitrary multipliers
    /// @dev Both legs floor-divide. The forward leg loses up to one ULP and the reverse leg loses
    ///      up to one more, so the round-trip can return a value strictly less than `x`. The
    ///      conservative invariant asserted here is `fromUIAmount(toUIAmount(x)) <= x`.
    function test_fromUIAmount_success_roundTripFloors(uint256 rawAmount, uint256 newMultiplier) public {
        // Bound the multiplier strictly below WAD to actually exercise the floor — at multipliers
        // >= WAD the forward leg loses nothing, so the round-trip is exact and uninteresting.
        rawAmount = bound(rawAmount, 0, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, asset().WAD_PRECISION() - 1);
        _updateMultiplier(newMultiplier);
        uint256 ui = asset().toUIAmount(rawAmount);
        uint256 roundTripped = asset().fromUIAmount(ui);
        assertLe(roundTripped, rawAmount, "round-trip must not exceed input (floors at each step)");
    }
}
