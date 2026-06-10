// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20AssetUpdateMultiplierTest is B20AssetTest {
    /// @notice Verifies updateMultiplier reverts when caller lacks OPERATOR_ROLE
    /// @dev Access control: only role-holders can rotate the multiplier; checks
    ///      AccessControlUnauthorizedAccount with OPERATOR_ROLE.
    function test_updateMultiplier_revert_unauthorized(address caller, uint256 newMultiplier) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE));
        asset().updateMultiplier(newMultiplier);
    }

    /// @notice Verifies updateMultiplier reverts when newMultiplier is zero
    /// @dev Input validation: zero is an invalid multiplier because stored zero is the
    ///      uninitialized-storage sentinel (read path normalizes it to WAD). Passing zero
    ///      would create an event/read inconsistency for off-chain indexers.
    function test_updateMultiplier_revert_zeroMultiplier() public {
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(IB20Asset.InvalidMultiplier.selector);
        asset().updateMultiplier(0);
    }

    /// @notice Verifies updateMultiplier writes the new value to the stored slot
    /// @dev State invariant: the stored slot holds the supplied multiplier verbatim (no clamping,
    ///      no scaling). Paired slot assertion verifies the storage write lands at the
    ///      multiplier slot.
    function test_updateMultiplier_success_writesSlot(uint256 newMultiplier) public {
        vm.assume(newMultiplier != 0);
        _updateMultiplier(newMultiplier);
        assertEq(
            uint256(vm.load(address(token), MockB20AssetStorage.multiplierSlot())),
            newMultiplier,
            "stored multiplier slot must reflect the write"
        );
    }

    /// @notice Verifies updateMultiplier emits MultiplierUpdated with the new value
    /// @dev Event integrity for the rotation; subscribers depend on this event to
    ///      re-derive holder scaled balances off-chain.
    function test_updateMultiplier_success_emitsEvent(uint256 newMultiplier) public {
        vm.assume(newMultiplier != 0);
        _grantOperator();
        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Asset.MultiplierUpdated(newMultiplier);
        vm.prank(operator);
        asset().updateMultiplier(newMultiplier);
    }
}
