// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Sequential check-order test for `grantRole`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRoleAdmin(role)` modifier) → `AccessControlUnauthorizedAccount`
///
///         Single condition: caller must hold the role's admin role. All roles
///         default to DEFAULT_ADMIN_ROLE as their admin, so an unauthorized caller
///         gets AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE).
///
///         The single test below fires the revert, grants the required role,
///         and verifies success.
contract B20GrantRoleRevertOrderTest is B20Test {
    function test_grantRole_revertOrder(address caller, bytes32 role, address account) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        // 1. ROLE fires (caller lacks DEFAULT_ADMIN_ROLE, which administers every role
        //    by default).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.grantRole(role, account);
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, caller);

        // Success — caller now holds the role admin.
        vm.prank(caller);
        token.grantRole(role, account);
    }
}
