// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20IsPausedTest is B20Test {
    /// @notice Verifies isPaused returns false for every feature on a freshly-created token
    /// @dev Default state across all PausableFeature enum values. Bound the fuzz input to the
    ///      3 defined ordinals (TRANSFER, MINT, BURN) to avoid Solidity's enum-decode
    ///      revert on out-of-range values.
    function test_isPaused_success_falseByDefault(uint8 featureInt) public view {
        IB20.PausableFeature feature = IB20.PausableFeature(uint8(bound(uint256(featureInt), 0, 2)));
        assertFalse(token.isPaused(feature), "fresh token must have no paused features");
    }

    /// @notice Verifies isPaused returns true after the feature is paused
    /// @dev State flip is observable per-feature
    function test_isPaused_success_trueAfterPause(uint8 featureInt) public {
        IB20.PausableFeature feature = IB20.PausableFeature(uint8(bound(uint256(featureInt), 0, 2)));
        _pause(feature);
        assertTrue(token.isPaused(feature), "feature must be paused after pause call");
    }

    /// @notice Verifies isPaused returns false again after the feature is unpaused
    /// @dev State flip back to inactive
    function test_isPaused_success_falseAfterUnpause(uint8 featureInt) public {
        IB20.PausableFeature feature = IB20.PausableFeature(uint8(bound(uint256(featureInt), 0, 2)));
        _pause(feature);
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(feature));
        assertFalse(token.isPaused(feature), "feature must be unpaused after unpause call");
    }
}
