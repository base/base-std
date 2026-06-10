// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20AssetMultiplierTest is B20AssetTest {
    /// @notice Verifies the default (unwritten) multiplier resolves to WAD_PRECISION
    /// @dev Freshly-etched token has stored multiplier = 0; the read surface fallback returns
    ///      WAD_PRECISION so the token reports a 1:1 multiplier without a factory write.
    function test_multiplier_success_defaultIsWad() public view {
        assertEq(asset().multiplier(), asset().WAD_PRECISION(), "default multiplier must equal WAD");
        // Paired slot assertion: the storage slot is genuinely zero on a fresh token.
        assertEq(
            uint256(vm.load(address(token), MockB20AssetStorage.multiplierSlot())),
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
        assertEq(asset().multiplier(), newMultiplier, "multiplier must equal the last written value");
        assertEq(
            uint256(vm.load(address(token), MockB20AssetStorage.multiplierSlot())),
            newMultiplier,
            "stored multiplier slot must hold the written value"
        );
    }

    /// @notice Verifies the WAD fallback applies when the stored slot is zero after a prior write
    /// @dev The read surface's `stored == 0 ? WAD : stored` sentinel applies regardless of whether
    ///      zero was the initial value or was written directly to the slot. `updateMultiplier(0)`
    ///      now reverts (InvalidMultiplier), so we zero the slot via vm.store to isolate the
    ///      read-path fallback from the write-path validation.
    function test_multiplier_success_zeroRestoresWadFallback() public {
        _updateMultiplier(5e18);
        vm.store(address(token), MockB20AssetStorage.multiplierSlot(), bytes32(0));
        assertEq(asset().multiplier(), asset().WAD_PRECISION(), "multiplier must collapse to WAD after zero");
    }
}
