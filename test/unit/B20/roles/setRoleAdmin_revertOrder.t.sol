// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Sequential check-order test for `setRoleAdmin`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(DEFAULT_ADMIN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         Single condition: caller must hold DEFAULT_ADMIN_ROLE. All roles
///         default to DEFAULT_ADMIN_ROLE as their admin, so an unauthorized caller
///         gets AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE).
///
///         The single test below fires the revert, grants DEFAULT_ADMIN_ROLE,
///         and verifies success.
contract B20SetRoleAdminRevertOrderTest is B20Test {
    function test_setRoleAdmin_revertOrder(address caller, bytes32 role, bytes32 newAdminRole) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        // 1. ROLE fires (caller lacks DEFAULT_ADMIN_ROLE).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.setRoleAdmin(role, newAdminRole);
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, caller);

        // Success — caller now holds DEFAULT_ADMIN_ROLE.
        vm.prank(caller);
        token.setRoleAdmin(role, newAdminRole);
    }
}
