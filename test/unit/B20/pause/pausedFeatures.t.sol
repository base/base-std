// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20PausedFeaturesTest is B20Test {
    /// @notice Verifies pausedFeatures returns an empty array on a freshly-created token
    /// @dev Default state: no features paused
    function test_pausedFeatures_success_emptyByDefault() public view {
        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 0, "fresh token must report no paused features");
    }

    /// @notice Verifies pausedFeatures returns the set of features paused via pause
    /// @dev Readback after one or more pause calls. The bitmask-to-enum-array conversion
    ///      iterates bits in ordinal order (TRANSFER=0, MINT=1, BURN=2), so
    ///      the returned array is sorted by enum ordinal.
    function test_pausedFeatures_success_reflectsPauseCalls() public {
        _pause(IB20.PausableFeature.BURN);
        _pause(IB20.PausableFeature.TRANSFER);

        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 2, "must list exactly two features");
        assertEq(uint256(features[0]), uint256(IB20.PausableFeature.TRANSFER), "ordinal 0 first");
        assertEq(uint256(features[1]), uint256(IB20.PausableFeature.BURN), "ordinal 2 second");
    }

    /// @notice Verifies pausedFeatures correctly reports BURN when it is the highest-ordinal paused feature
    /// @dev BURN is the last (highest-ordinal) feature in PausableFeature. A loop bound
    ///      off-by-one (e.g. `i < 2` instead of `i < 3`) would silently miss BURN in the
    ///      returned array. Explicit single-feature test catches the loop-bound bug.
    function test_pausedFeatures_success_includesHighestOrdinal() public {
        _pause(IB20.PausableFeature.BURN);

        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 1, "must list exactly one feature");
        assertEq(uint256(features[0]), uint256(IB20.PausableFeature.BURN), "must be BURN");
    }

    /// @notice Verifies pausedFeatures returns the set minus features removed via unpause
    /// @dev Readback after partial unpause
    function test_pausedFeatures_success_reflectsUnpauseCalls() public {
        _pause(IB20.PausableFeature.TRANSFER);
        _pause(IB20.PausableFeature.MINT);
        _pause(IB20.PausableFeature.BURN);

        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.MINT));

        IB20.PausableFeature[] memory features = token.pausedFeatures();
        assertEq(features.length, 2, "must list two features after partial unpause");
        assertEq(uint256(features[0]), uint256(IB20.PausableFeature.TRANSFER), "TRANSFER still paused");
        assertEq(uint256(features[1]), uint256(IB20.PausableFeature.BURN), "BURN still paused");
    }
}
