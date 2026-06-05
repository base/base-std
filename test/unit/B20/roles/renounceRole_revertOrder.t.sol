// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `renounceRole`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. BAD-CONFIRMATION (`callerConfirmation != msg.sender`) → `AccessControlBadConfirmation`
///         2. LAST-ADMIN (role == DEFAULT_ADMIN && caller holds it && adminCount == 1) → `LastAdminCannotRenounce`
///
///         C(2, 2) = 1 pair.
contract B20RenounceRoleRevertOrderTest is B20Test {
    /// @notice BAD-CONFIRMATION beats LAST-ADMIN.
    /// @dev Caller is the sole admin (LAST-ADMIN would fire) AND passes a wrong confirmation.
    ///      Confirmation check runs before the last-admin guard.
    function test_renounceRole_revertOrder_badConfirmation_beats_lastAdmin(address wrongConfirmation) public {
        vm.assume(wrongConfirmation != admin);
        // admin is the sole admin by default (precondition for LAST-ADMIN).

        vm.prank(admin);
        vm.expectRevert(IB20.AccessControlBadConfirmation.selector);
        token.renounceRole(B20Constants.DEFAULT_ADMIN_ROLE, wrongConfirmation);
    }
}
