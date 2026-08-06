// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20AssetToUIAmountTest is B20AssetTest {
    /// @notice Verifies toUIAmount is the identity on a fresh token (WAD multiplier)
    /// @dev Default multiplier is WAD, so rawAmount * WAD / WAD == rawAmount for every input.
    function test_toUIAmount_success_identityOnWadDefault(uint256 rawAmount) public view {
        rawAmount = bound(rawAmount, 0, type(uint256).max / asset().WAD_PRECISION());
        assertEq(asset().toUIAmount(rawAmount), rawAmount, "default multiplier must produce identity");
    }

    /// @notice Verifies toUIAmount scales by the stored multiplier after an update
    /// @dev Property: toUIAmount(rawAmount) == rawAmount * multiplier / WAD. Fuzz both
    ///      inputs over the range that avoids the intermediate-product overflow.
    function test_toUIAmount_success_scalesByStoredMultiplier(uint256 rawAmount, uint256 newMultiplier) public {
        rawAmount = bound(rawAmount, 0, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(
            asset().toUIAmount(rawAmount),
            (rawAmount * newMultiplier) / asset().WAD_PRECISION(),
            "toUIAmount must apply rawAmount * multiplier / WAD"
        );
    }

    /// @notice Verifies toUIAmount of zero rawAmount is zero regardless of the multiplier
    /// @dev Degenerate input edge: any multiplier multiplied into zero is zero.
    function test_toUIAmount_success_zeroRawAmount(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(asset().toUIAmount(0), 0, "zero rawAmount must produce zero UI amount");
    }

    /// @notice Verifies toUIAmount applies the WAD fallback when the stored multiplier is zero
    /// @dev A stored `multiplier` of zero resolves as `WAD_PRECISION` on the read surface.
    ///      `updateMultiplier(0)` now reverts (InvalidMultiplier), so we zero the slot via
    ///      vm.store to isolate the read-path fallback from write-path validation.
    function test_toUIAmount_success_explicitZeroMultiplierFallsBackToWad(uint256 rawAmount) public {
        rawAmount = bound(rawAmount, 0, type(uint128).max);
        _updateMultiplier(5e18); // seed a non-zero value first
        vm.store(address(token), MockB20AssetStorage.multiplierSlot(), bytes32(0)); // zero the slot directly
        assertEq(
            asset().toUIAmount(rawAmount), rawAmount, "stored zero multiplier must produce identity (WAD fallback)"
        );
    }

    /// @notice Verifies toUIAmount reverts when rawAmount * multiplier overflows uint256
    /// @dev The Rust precompile uses checked multiplication and reverts on overflow; the Solidity
    ///      reference relies on 0.8.x checked arithmetic (Panic 0x11). The success tests bound inputs
    ///      to avoid the overflow, leaving the boundary itself untested. A generic expectRevert keeps
    ///      the assertion robust across the mock (Panic) and the live precompile's overflow error.
    function test_toUIAmount_revert_arithmeticOverflow(uint256 rawAmount, uint256 newMultiplier) public {
        // The multiplier is capped at `type(uint128).max` by the setter; overflow is still
        // reachable because `rawAmount` (an arbitrary conversion input, not bounded by supply)
        // can be pushed high enough that `rawAmount * multiplier` exceeds `type(uint256).max`.
        newMultiplier = bound(newMultiplier, 2, type(uint128).max);
        // Force rawAmount * multiplier strictly above type(uint256).max.
        rawAmount = bound(rawAmount, type(uint256).max / newMultiplier + 1, type(uint256).max);
        _updateMultiplier(newMultiplier);

        vm.expectRevert();
        asset().toUIAmount(rawAmount);
    }
}
