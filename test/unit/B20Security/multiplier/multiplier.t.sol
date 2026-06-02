// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {MockB20SecurityStorage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SecurityMultiplierTest is B20SecurityTest {
    /// @notice Verifies the default (unwritten) multiplier resolves to WAD_PRECISION
    /// @dev Freshly-etched token has stored multiplier = 0; the read surface fallback returns
    ///      WAD_PRECISION so the token reports a 1:1 multiplier without a factory write.
    function test_multiplier_success_defaultIsWad() public view {
        assertEq(security().multiplier(), security().WAD_PRECISION(), "default multiplier must equal WAD");
        // Paired slot assertion: the storage slot is genuinely zero on a fresh token.
        assertEq(
            uint256(vm.load(address(token), MockB20SecurityStorage.multiplierSlot())),
            0,
            "stored multiplier slot must be zero before any write"
        );
    }

    /// @notice Verifies the multiplier reads back the stored value after a write
    /// @dev Fuzz over arbitrary non-zero multipliers; the read surface returns the stored value
    ///      verbatim (no rescaling, no clamping).
    function test_multiplier_success_returnsStoredValue(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint256).max);
        _updateMultiplier(newMultiplier);
        assertEq(security().multiplier(), newMultiplier, "multiplier must equal the last written value");
        assertEq(
            uint256(vm.load(address(token), MockB20SecurityStorage.multiplierSlot())),
            newMultiplier,
            "stored multiplier slot must hold the written value"
        );
    }

    /// @notice Verifies writing zero re-activates the WAD fallback
    /// @dev Operator can revert to the default 1:1 multiplier by writing 0; the read surface's
    ///      `stored == 0 ? WAD : stored` collapses zero back to WAD.
    function test_multiplier_success_zeroRestoresWadFallback() public {
        _updateMultiplier(5e18);
        _updateMultiplier(0);
        assertEq(security().multiplier(), security().WAD_PRECISION(), "multiplier must collapse to WAD after zero");
    }
}
