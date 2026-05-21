// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {B20Constants} from "src/lib/B20Constants.sol";
import {MockB20RedeemStorage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SecurityUpdateMinimumRedeemableTest is B20SecurityTest {
    /// @notice Verifies updateMinimumRedeemable reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: gated on DEFAULT_ADMIN_ROLE (NOT SECURITY_OPERATOR_ROLE).
    ///      Checks AccessControlUnauthorizedAccount with DEFAULT_ADMIN_ROLE in the revert.
    function test_updateMinimumRedeemable_revert_unauthorized(address caller, uint256 newMinimum) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        security().updateMinimumRedeemable(newMinimum);
    }

    /// @notice Verifies updateMinimumRedeemable writes the supplied value to the stored slot
    /// @dev State invariant: stored slot holds the supplied value verbatim. Paired slot
    ///      assertion checks the write lands at the minimumRedeemable slot.
    function test_updateMinimumRedeemable_success_writesSlot(uint256 newMinimum) public {
        _updateMinimumRedeemable(newMinimum);
        assertEq(
            uint256(vm.load(address(token), MockB20RedeemStorage.minimumRedeemableSlot())),
            newMinimum,
            "stored minimumRedeemable slot must reflect the write"
        );
    }

    /// @notice Verifies updateMinimumRedeemable emits MinimumRedeemableUpdated(caller, new)
    /// @dev Event integrity for the floor change; caller is indexed so off-chain consumers
    ///      can attribute the change to the specific admin who rotated it.
    function test_updateMinimumRedeemable_success_emitsEvent(uint256 newMinimum) public {
        vm.expectEmit(true, false, false, true, address(token));
        emit IB20Security.MinimumRedeemableUpdated(admin, newMinimum);
        vm.prank(admin);
        security().updateMinimumRedeemable(newMinimum);
    }
}
