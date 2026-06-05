// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetPrecisionConstantsTest is B20AssetTest {
    /// @notice Verifies WAD_PRECISION equals 1e18
    /// @dev DeFi convention check: `toScaledBalance` and `scaledBalanceOf` divide by this after
    ///      multiplying by the stored multiplier (and `toRawBalance` multiplies by this before
    ///      dividing); any drift silently rescales every holder's scaled balance.
    function test_wadPrecision_success_equalsOneWad() public view {
        assertEq(asset().WAD_PRECISION(), 1e18, "WAD_PRECISION must equal 1e18");
    }
}
