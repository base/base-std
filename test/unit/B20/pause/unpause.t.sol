// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20UnpauseTest is B20Test {
    /// @notice Verifies unpause reverts when caller lacks UNPAUSE_ROLE
    /// @dev Access control: only role-holders can unpause; checks AccessControlUnauthorizedAccount
    function test_unpause_revert_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.UNPAUSE_ROLE)
        );
        token.unpause(_singleFeature(IB20.PausableFeature.TRANSFER));
    }

    /// @notice Verifies unpause reverts for an empty features array
    /// @dev Input validation: empty unpause set is meaningless; checks EmptyFeatureSet() error
    function test_unpause_revert_emptyFeatureSet() public {
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);

        vm.prank(unpauser);
        vm.expectRevert(IB20.EmptyFeatureSet.selector);
        token.unpause(new IB20.PausableFeature[](0));
    }

    /// @notice Verifies unpause clears each listed feature from pausedFeatures
    /// @dev State transition: each feature is removed; non-listed features remain unchanged.
    ///      Paired slot assertion: `pausedVectors` slot holds only the
    ///      MINT bit after the TRANSFER bit is cleared.
    function test_unpause_success_clearsListedFeatures() public {
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);

        // Pause two features so we have something to unpause.
        _pause(IB20.PausableFeature.TRANSFER);
        _pause(IB20.PausableFeature.MINT);

        // Unpause only TRANSFER.
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.TRANSFER));

        assertFalse(token.isPaused(IB20.PausableFeature.TRANSFER), "TRANSFER must be unpaused");
        assertTrue(token.isPaused(IB20.PausableFeature.MINT), "MINT must remain paused");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.pausedVectorsSlot())),
            1 << uint8(IB20.PausableFeature.MINT),
            "pausedVectors slot must hold only the MINT bit after TRANSFER unpause"
        );
    }

    /// @notice Verifies unpause is idempotent when called with not-currently-paused features
    /// @dev No state change and no revert for features that are already inactive.
    ///      Paired slot assertion: `pausedVectors` slot remains zero.
    function test_unpause_success_idempotentForUnpaused() public {
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);

        // BURN is not paused.
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.BURN));

        assertFalse(token.isPaused(IB20.PausableFeature.BURN), "BURN remains unpaused");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.pausedVectorsSlot())),
            0,
            "pausedVectors slot must remain zero when unpausing a not-paused feature"
        );
    }

    /// @notice Verifies unpause emits Unpaused(caller, features) with the call's argument
    /// @dev Event integrity; canonical Unpaused emission test
    function test_unpause_success_emitsUnpaused() public {
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        _pause(IB20.PausableFeature.TRANSFER);

        IB20.PausableFeature[] memory features = _singleFeature(IB20.PausableFeature.TRANSFER);

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.Unpaused(unpauser, features);
        vm.prank(unpauser);
        token.unpause(features);
    }
}
