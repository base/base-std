// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {MockB20SecurityStorage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SecurityUpdateShareRatioTest is B20SecurityTest {
    /// @notice Verifies updateShareRatio reverts when caller lacks SECURITY_OPERATOR_ROLE
    /// @dev Access control: only role-holders can rotate the ratio; checks
    ///      AccessControlUnauthorizedAccount with SECURITY_OPERATOR_ROLE.
    function test_updateShareRatio_revert_unauthorized(address caller, uint256 newRatio) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, SECURITY_OPERATOR_ROLE)
        );
        security().updateShareRatio(newRatio);
    }

    /// @notice Verifies updateShareRatio writes the new value to the stored slot
    /// @dev State invariant: the stored slot holds the supplied ratio verbatim (no clamping,
    ///      no scaling). Paired slot assertion verifies the storage write lands at the
    ///      sharesToTokensRatio slot.
    function test_updateShareRatio_success_writesSlot(uint256 newRatio) public {
        _updateShareRatio(newRatio);
        assertEq(
            uint256(vm.load(address(token), MockB20SecurityStorage.sharesToTokensRatioSlot())),
            newRatio,
            "stored ratio slot must reflect the write"
        );
    }

    /// @notice Verifies updateShareRatio emits ShareRatioUpdated with the new value
    /// @dev Event integrity for the rotation; subscribers depend on this event to
    ///      re-derive holder share counts off-chain.
    function test_updateShareRatio_success_emitsEvent(uint256 newRatio) public {
        _grantOperator();
        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Security.ShareRatioUpdated(newRatio);
        vm.prank(operator);
        security().updateShareRatio(newRatio);
    }
}
