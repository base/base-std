// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `revokeRole`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRoleAdmin(role)` modifier) → `AccessControlUnauthorizedAccount`
///         2. LAST-ADMIN (`role == DEFAULT_ADMIN && account holds it && adminCount == 1`)
///            → `LastAdminCannotRenounce`
///
///         C(2, 2) = 1 pair. Without the LAST-ADMIN guard, `revokeRole` would silently
///         brick the token by removing the sole admin.
contract B20RevokeRoleRevertOrderTest is B20Test {
    /// @notice ROLE beats LAST-ADMIN.
    /// @dev Caller lacks the role-admin role AND the target is the sole DEFAULT_ADMIN_ROLE holder.
    ///      The `onlyRoleAdmin` modifier runs before the body's last-admin guard.
    function test_revokeRole_revertOrder_role_beats_lastAdmin(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        // admin is the sole DEFAULT_ADMIN_ROLE holder by default.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.revokeRole(B20Constants.DEFAULT_ADMIN_ROLE, admin);
    }
}
