// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetTotalSupplyUITest is B20AssetTest {
    /// @notice Verifies totalSupplyUI scales the raw total supply by the active multiplier
    /// @dev Property: totalSupplyUI == totalSupply * multiplier / WAD.
    function test_totalSupplyUI_success_scalesByMultiplier(uint256 amount, uint256 newMultiplier) public {
        amount = bound(amount, 1, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _mint(alice, amount);
        _updateMultiplier(newMultiplier);
        assertEq(
            asset().totalSupplyUI(),
            (token.totalSupply() * newMultiplier) / asset().WAD_PRECISION(),
            "totalSupplyUI must apply totalSupply * multiplier / WAD"
        );
    }

    /// @notice Verifies totalSupplyUI is zero when no supply has been minted
    function test_totalSupplyUI_success_zeroWhenNoSupply(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _updateMultiplier(newMultiplier);
        assertEq(asset().totalSupplyUI(), 0, "no supply: totalSupplyUI must be zero regardless of multiplier");
    }
}
