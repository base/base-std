// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20SetRoleAdminTest is B20Test {
    /// @notice Verifies setRoleAdmin reverts when caller does not hold the role's current admin role
    /// @dev Access control: caller must hold the current getRoleAdmin(role); checks AccessControlUnauthorizedAccount.
    ///      For a freshly-created token, every role's admin defaults to DEFAULT_ADMIN_ROLE.
    function test_setRoleAdmin_revert_unauthorized(address caller, bytes32 role, bytes32 newAdminRole) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.setRoleAdmin(role, newAdminRole);
    }

    /// @notice Verifies setRoleAdmin updates getRoleAdmin(role) to the new admin role
    /// @dev Read-after-write; canonical getRoleAdmin readback test lives in getRoleAdmin.t.sol.
    ///      Paired slot assertion: `roleAdmins[role]` slot reflects newAdminRole.
    function test_setRoleAdmin_success_updatesAdmin(bytes32 role, bytes32 newAdminRole) public {
        vm.prank(admin);
        token.setRoleAdmin(role, newAdminRole);
        assertEq(token.getRoleAdmin(role), newAdminRole, "getRoleAdmin must reflect setRoleAdmin");
        assertEq(
            vm.load(address(token), MockB20Storage.roleAdminSlot(role)),
            newAdminRole,
            "roleAdmins[role] slot must reflect setRoleAdmin"
        );
    }

    /// @notice Verifies setRoleAdmin emits RoleAdminChanged(role, previousAdminRole, newAdminRole)
    /// @dev Event integrity; canonical RoleAdminChanged emission test.
    ///      Every role on a fresh token is unconfigured, so the previous
    ///      admin reads as the storage zero-default `bytes32(0)`, which
    ///      IS `DEFAULT_ADMIN_ROLE`. The same value covers both the
    ///      DEFAULT_ADMIN_ROLE-itself case and every other role.
    function test_setRoleAdmin_success_emitsRoleAdminChanged(bytes32 role, bytes32 newAdminRole) public {
        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.RoleAdminChanged(role, bytes32(0), newAdminRole);
        vm.prank(admin);
        token.setRoleAdmin(role, newAdminRole);
    }
}
