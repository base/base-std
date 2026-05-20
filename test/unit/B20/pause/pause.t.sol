// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

contract B20PauseTest is B20Test {
    /// @notice Verifies pause reverts when caller lacks PAUSE_ROLE
    /// @dev Access control: only role-holders can pause; checks AccessControlUnauthorizedAccount
    function test_pause_revert_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        // No pause role granted to caller.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.PAUSE_ROLE)
        );
        token.pause(_singleFeature(IB20.PausableFeature.TRANSFER));
    }

    /// @notice Verifies pause reverts for an empty features array
    /// @dev Input validation: empty pause set is meaningless; checks EmptyFeatureSet() error
    function test_pause_revert_emptyFeatureSet() public {
        _grantRole(B20Constants.PAUSE_ROLE, pauser);

        vm.prank(pauser);
        vm.expectRevert(IB20.EmptyFeatureSet.selector);
        token.pause(new IB20.PausableFeature[](0));
    }

    /// @notice Verifies pause sets each listed feature in pausedFeatures
    /// @dev State transition: each feature becomes observable via isPaused after the call
    function test_pause_success_setsFeatures() public {
        _grantRole(B20Constants.PAUSE_ROLE, pauser);

        IB20.PausableFeature[] memory features = new IB20.PausableFeature[](2);
        features[0] = IB20.PausableFeature.TRANSFER;
        features[1] = IB20.PausableFeature.MINT;

        vm.prank(pauser);
        token.pause(features);

        assertTrue(token.isPaused(IB20.PausableFeature.TRANSFER), "TRANSFER must be paused");
        assertTrue(token.isPaused(IB20.PausableFeature.MINT), "MINT must be paused");
        assertFalse(token.isPaused(IB20.PausableFeature.BURN), "BURN must remain unpaused");
        assertFalse(token.isPaused(IB20.PausableFeature.REDEEM), "REDEEM must remain unpaused");
    }

    /// @notice Verifies pause is additive over multiple calls
    /// @dev Sequential pauses union into the existing set; prior features remain paused
    function test_pause_success_additiveAcrossCalls() public {
        _grantRole(B20Constants.PAUSE_ROLE, pauser);

        vm.prank(pauser);
        token.pause(_singleFeature(IB20.PausableFeature.TRANSFER));
        vm.prank(pauser);
        token.pause(_singleFeature(IB20.PausableFeature.MINT));

        assertTrue(token.isPaused(IB20.PausableFeature.TRANSFER), "TRANSFER still paused");
        assertTrue(token.isPaused(IB20.PausableFeature.MINT), "MINT paused");
    }

    /// @notice Verifies pause is idempotent when called with already-paused features
    /// @dev Duplicate entries do not change state and do not revert
    function test_pause_success_idempotent() public {
        _grantRole(B20Constants.PAUSE_ROLE, pauser);

        vm.prank(pauser);
        token.pause(_singleFeature(IB20.PausableFeature.TRANSFER));
        // Second pause of the same feature: no revert.
        vm.prank(pauser);
        token.pause(_singleFeature(IB20.PausableFeature.TRANSFER));

        assertTrue(token.isPaused(IB20.PausableFeature.TRANSFER), "still paused");
    }

    /// @notice Verifies pause emits Paused(caller, features) with the call's argument
    /// @dev Event integrity; canonical Paused emission test
    function test_pause_success_emitsPaused() public {
        _grantRole(B20Constants.PAUSE_ROLE, pauser);

        IB20.PausableFeature[] memory features = _singleFeature(IB20.PausableFeature.TRANSFER);

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.Paused(pauser, features);
        vm.prank(pauser);
        token.pause(features);
    }
}
