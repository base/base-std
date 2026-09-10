// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20GetRoleAdminTest is B20Test {
    /// @notice Verifies OPERATOR_ROLE is administered by DEFAULT_ADMIN_ROLE on a fresh token
    /// @dev Pins the selected governance default for issuer-approved operators.
    function test_getRoleAdmin_success_operatorDefaultsToAdminRole() public view {
        assertEq(
            token.getRoleAdmin(B20Constants.OPERATOR_ROLE),
            B20Constants.DEFAULT_ADMIN_ROLE,
            "operator role must default to DEFAULT_ADMIN_ROLE"
        );
    }

    /// @notice Verifies getRoleAdmin returns DEFAULT_ADMIN_ROLE for any role that hasn't been customized
    /// @dev OZ AccessControl default: every role is administered by DEFAULT_ADMIN_ROLE unless overridden.
    ///      DEFAULT_ADMIN_ROLE itself is its own admin (returns bytes32(0)), so filter that out here;
    ///      that special case is covered implicitly by the setRoleAdmin-emits test.
    function test_getRoleAdmin_success_defaultsToAdminRole(bytes32 role) public view {
        vm.assume(role != B20Constants.DEFAULT_ADMIN_ROLE);
        assertEq(
            token.getRoleAdmin(role),
            B20Constants.DEFAULT_ADMIN_ROLE,
            "default admin must be B20Constants.DEFAULT_ADMIN_ROLE"
        );
    }

    /// @notice Verifies getRoleAdmin returns the new admin role after setRoleAdmin
    /// @dev Read-after-write for role-admin reassignment
    function test_getRoleAdmin_success_reflectsSetRoleAdmin(bytes32 role, bytes32 newAdminRole) public {
        vm.prank(admin);
        token.setRoleAdmin(role, newAdminRole);
        assertEq(token.getRoleAdmin(role), newAdminRole, "getRoleAdmin must reflect setRoleAdmin");
    }
}
