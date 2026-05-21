// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

contract B20UpdateRoleAdminTest is B20Test {
    /// @notice Verifies updateRoleAdmin reverts when caller does not hold the role's current admin role
    /// @dev Access control: caller must hold the current getRoleAdmin(role); checks AccessControlUnauthorizedAccount.
    ///      For a freshly-created token, every role's admin defaults to DEFAULT_ADMIN_ROLE.
    function test_updateRoleAdmin_revert_unauthorized(address caller, bytes32 role, bytes32 newAdminRole) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updateRoleAdmin(role, newAdminRole);
    }

    /// @notice Verifies updateRoleAdmin updates getRoleAdmin(role) to the new admin role
    /// @dev Read-after-write; canonical getRoleAdmin readback test lives in getRoleAdmin.t.sol.
    ///      Paired slot assertion: `roleAdmins[role]` slot reflects newAdminRole.
    function test_updateRoleAdmin_success_updatesAdmin(bytes32 role, bytes32 newAdminRole) public {
        vm.prank(admin);
        token.updateRoleAdmin(role, newAdminRole);
        assertEq(token.getRoleAdmin(role), newAdminRole, "getRoleAdmin must reflect updateRoleAdmin");
        assertEq(
            vm.load(address(token), MockB20Storage.roleAdminSlot(role)),
            newAdminRole,
            "roleAdmins[role] slot must reflect updateRoleAdmin"
        );
    }

    /// @notice Verifies updateRoleAdmin emits RoleAdminChanged(role, previousAdminRole, newAdminRole)
    /// @dev Event integrity; canonical RoleAdminChanged emission test.
    ///      For an unconfigured non-default role, previousAdminRole is the implied
    ///      DEFAULT_ADMIN_ROLE; for DEFAULT_ADMIN_ROLE itself, previous is bytes32(0).
    function test_updateRoleAdmin_success_emitsRoleAdminChanged(bytes32 role, bytes32 newAdminRole) public {
        bytes32 previousAdminRole =
            role == B20Constants.DEFAULT_ADMIN_ROLE ? bytes32(0) : B20Constants.DEFAULT_ADMIN_ROLE;

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.RoleAdminChanged(role, previousAdminRole, newAdminRole);
        vm.prank(admin);
        token.updateRoleAdmin(role, newAdminRole);
    }
}
