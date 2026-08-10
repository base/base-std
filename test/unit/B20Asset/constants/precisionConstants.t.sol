// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetPrecisionConstantsTest is B20AssetTest {
    /// @notice Verifies WAD_PRECISION equals 1e18
    /// @dev DeFi convention check: `toUIAmount` and `scaledBalanceOf` divide by this after
    ///      multiplying by the stored multiplier (and `fromUIAmount` multiplies by this before
    ///      dividing); any drift silently rescales every holder's scaled balance.
    function test_wadPrecision_success_equalsOneWad() public view {
        assertEq(asset().WAD_PRECISION(), 1e18, "WAD_PRECISION must equal 1e18");
    }

    /// @notice Verifies MAX_UI_MULTIPLIER equals type(uint128).max
    /// @dev The setters reject `newMultiplier > MAX_UI_MULTIPLIER`; exposing the bound as a getter
    ///      lets callers read it without hitting the revert path. Pins it to the uint128 overflow
    ///      guard so a drift can't silently widen (or narrow) the accepted multiplier range.
    function test_maxUIMultiplier_success_equalsUint128Max() public view {
        assertEq(asset().MAX_UI_MULTIPLIER(), type(uint128).max, "MAX_UI_MULTIPLIER must equal type(uint128).max");
    }
}
