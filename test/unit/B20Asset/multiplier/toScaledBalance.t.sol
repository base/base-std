// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetToScaledBalanceTest is B20AssetTest {
    /// @notice Verifies toScaledBalance is the identity on a fresh token (WAD multiplier)
    /// @dev Default multiplier is WAD, so rawBalance * WAD / WAD == rawBalance for every input.
    function test_toScaledBalance_success_identityOnWadDefault(uint256 rawBalance) public view {
        rawBalance = bound(rawBalance, 0, type(uint256).max / asset().WAD_PRECISION());
        assertEq(asset().toScaledBalance(rawBalance), rawBalance, "default multiplier must produce identity");
    }

    /// @notice Verifies toScaledBalance scales by the stored multiplier after an update
    /// @dev Property: toScaledBalance(rawBalance) == rawBalance * multiplier / WAD. Fuzz both
    ///      inputs over the range that avoids the intermediate-product overflow.
    function test_toScaledBalance_success_scalesByStoredMultiplier(uint256 rawBalance, uint256 newMultiplier) public {
        rawBalance = bound(rawBalance, 0, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(
            asset().toScaledBalance(rawBalance),
            (rawBalance * newMultiplier) / asset().WAD_PRECISION(),
            "toScaledBalance must apply rawBalance * multiplier / WAD"
        );
    }

    /// @notice Verifies toScaledBalance of zero rawBalance is zero regardless of the multiplier
    /// @dev Degenerate input edge: any multiplier multiplied into zero is zero.
    function test_toScaledBalance_success_zeroRawBalance(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint256).max);
        _updateMultiplier(newMultiplier);
        assertEq(asset().toScaledBalance(0), 0, "zero rawBalance must produce zero scaled balance");
    }

    /// @notice Verifies toScaledBalance applies the WAD fallback when the stored multiplier is explicitly zero
    /// @dev A stored `multiplier` of zero is documented to resolve as `WAD_PRECISION` on the read
    ///      surface, both pre-write (fresh slot) and post-explicit-zero-write. Tests the latter:
    ///      after writing zero, toScaledBalance must behave as if the multiplier were WAD
    ///      (identity). Cross-references test_multiplier_success_zeroRestoresWadFallback at the
    ///      derived-function level so a refactor that reads the slot directly here would fail.
    function test_toScaledBalance_success_explicitZeroMultiplierFallsBackToWad(uint256 rawBalance) public {
        rawBalance = bound(rawBalance, 0, type(uint128).max);
        _updateMultiplier(5e18); // seed a non-zero value first
        _updateMultiplier(0); // then explicitly clear back to zero
        assertEq(
            asset().toScaledBalance(rawBalance),
            rawBalance,
            "stored zero multiplier must produce identity (WAD fallback)"
        );
    }

    /// @notice Verifies toScaledBalance reverts when rawBalance * multiplier overflows uint256
    /// @dev The Rust precompile uses checked multiplication and reverts on overflow; the Solidity
    ///      reference relies on 0.8.x checked arithmetic (Panic 0x11). The success tests bound inputs
    ///      to avoid the overflow, leaving the boundary itself untested. A generic expectRevert keeps
    ///      the assertion robust across the mock (Panic) and the live precompile's overflow error.
    function test_toScaledBalance_revert_arithmeticOverflow(uint256 rawBalance, uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 2, type(uint256).max);
        // Force rawBalance * multiplier strictly above type(uint256).max.
        rawBalance = bound(rawBalance, type(uint256).max / newMultiplier + 1, type(uint256).max);
        _updateMultiplier(newMultiplier);

        vm.expectRevert();
        asset().toScaledBalance(rawBalance);
    }
}
