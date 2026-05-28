// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecurityToSharesTest is B20SecurityTest {
    /// @notice Verifies toShares is the identity on a fresh token (WAD ratio)
    /// @dev Default ratio is WAD, so balance * WAD / WAD == balance for every input.
    function test_toShares_success_identityOnWadDefault(uint256 balance) public view {
        balance = bound(balance, 0, type(uint256).max / security().WAD_PRECISION());
        assertEq(security().toShares(balance), balance, "default ratio must produce identity");
    }

    /// @notice Verifies toShares scales by the stored ratio after an update
    /// @dev Property: toShares(balance) == balance * ratio / WAD. Fuzz both inputs over the
    ///      range that avoids the intermediate-product overflow.
    function test_toShares_success_scalesByStoredRatio(uint256 balance, uint256 ratio) public {
        balance = bound(balance, 0, type(uint128).max);
        ratio = bound(ratio, 1, type(uint128).max);
        _updateShareRatio(ratio);
        assertEq(
            security().toShares(balance),
            (balance * ratio) / security().WAD_PRECISION(),
            "toShares must apply balance * ratio / WAD"
        );
    }

    /// @notice Verifies toShares of zero balance is zero regardless of the ratio
    /// @dev Degenerate input edge: any ratio multiplied into zero is zero.
    function test_toShares_success_zeroBalance(uint256 ratio) public {
        ratio = bound(ratio, 1, type(uint256).max);
        _updateShareRatio(ratio);
        assertEq(security().toShares(0), 0, "zero balance must produce zero shares");
    }

    /// @notice Verifies toShares applies the WAD fallback when the stored ratio is explicitly zero
    /// @dev A stored `sharesToTokensRatio` of zero is documented to resolve as `WAD_PRECISION` on
    ///      the read surface, both pre-write (fresh slot) and post-explicit-zero-write. Tests the
    ///      latter: after writing zero, toShares must behave as if the ratio were WAD (identity).
    ///      Cross-references test_sharesToTokensRatio_success_zeroRestoresWadFallback at the
    ///      derived-function level so a refactor that reads the slot directly here would fail.
    function test_toShares_success_explicitZeroRatioFallsBackToWad(uint256 balance) public {
        balance = bound(balance, 0, type(uint128).max);
        _updateShareRatio(5e18); // seed a non-zero value first
        _updateShareRatio(0);    // then explicitly clear back to zero
        assertEq(security().toShares(balance), balance, "stored zero ratio must produce identity (WAD fallback)");
    }
}
