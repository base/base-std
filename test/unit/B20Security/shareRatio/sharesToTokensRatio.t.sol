// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {MockB20SecurityStorage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SecuritySharesToTokensRatioTest is B20SecurityTest {
    /// @notice Verifies the default (unwritten) ratio resolves to WAD_PRECISION
    /// @dev Freshly-etched token has stored ratio = 0; the read surface fallback returns
    ///      WAD_PRECISION so the token reports a 1:1 ratio without a factory write.
    function test_sharesToTokensRatio_success_defaultIsWad() public view {
        assertEq(security().sharesToTokensRatio(), security().WAD_PRECISION(), "default ratio must equal WAD");
        // Paired slot assertion: the storage slot is genuinely zero on a fresh token.
        assertEq(
            uint256(vm.load(address(token), MockB20SecurityStorage.sharesToTokensRatioSlot())),
            0,
            "stored ratio slot must be zero before any write"
        );
    }

    /// @notice Verifies the ratio reads back the stored value after a write
    /// @dev Fuzz over arbitrary non-zero ratios; the read surface returns the stored value
    ///      verbatim (no rescaling, no clamping).
    function test_sharesToTokensRatio_success_returnsStoredValue(uint256 newRatio) public {
        newRatio = bound(newRatio, 1, type(uint256).max);
        _updateShareRatio(newRatio);
        assertEq(security().sharesToTokensRatio(), newRatio, "ratio must equal the last written value");
        assertEq(
            uint256(vm.load(address(token), MockB20SecurityStorage.sharesToTokensRatioSlot())),
            newRatio,
            "stored ratio slot must hold the written value"
        );
    }

    /// @notice Verifies writing zero re-activates the WAD fallback
    /// @dev Operator can revert to the default 1:1 ratio by writing 0; the read surface's
    ///      `stored == 0 ? WAD : stored` collapses zero back to WAD.
    function test_sharesToTokensRatio_success_zeroRestoresWadFallback() public {
        _updateShareRatio(5e18);
        _updateShareRatio(0);
        assertEq(security().sharesToTokensRatio(), security().WAD_PRECISION(), "ratio must collapse to WAD after zero");
    }
}
