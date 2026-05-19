// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20PausedFeaturesTest is B20Test {
    /// @notice Verifies pausedFeatures returns an empty array on a freshly-created token
    /// @dev Default state: no features paused
    function test_pausedFeatures_success_emptyByDefault() public view {
        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 0, "fresh token must report no paused features");
    }

    /// @notice Verifies pausedFeatures returns the set of features paused via pause
    /// @dev Readback after one or more pause calls. The bitmask-to-enum-array conversion
    ///      iterates bits in ordinal order (TRANSFER=0, MINT=1, BURN=2, REDEEM=3), so
    ///      the returned array is sorted by enum ordinal.
    function test_pausedFeatures_success_reflectsPauseCalls() public {
        _pause(IB20.PausableFeature.BURN);
        _pause(IB20.PausableFeature.TRANSFER);

        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 2, "must list exactly two features");
        assertEq(uint256(features[0]), uint256(IB20.PausableFeature.TRANSFER), "ordinal 0 first");
        assertEq(uint256(features[1]), uint256(IB20.PausableFeature.BURN), "ordinal 2 second");
    }

    /// @notice Verifies pausedFeatures returns the set minus features removed via unpause
    /// @dev Readback after partial unpause
    function test_pausedFeatures_success_reflectsUnpauseCalls() public {
        _pause(IB20.PausableFeature.TRANSFER);
        _pause(IB20.PausableFeature.MINT);
        _pause(IB20.PausableFeature.BURN);

        _grantRole(UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.MINT));

        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 2, "must list two features after partial unpause");
        assertEq(uint256(features[0]), uint256(IB20.PausableFeature.TRANSFER), "TRANSFER still paused");
        assertEq(uint256(features[1]), uint256(IB20.PausableFeature.BURN), "BURN still paused");
    }
}
