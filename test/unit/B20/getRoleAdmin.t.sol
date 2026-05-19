// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20GetRoleAdminTest is B20Test {
    /// @notice Verifies getRoleAdmin returns DEFAULT_ADMIN_ROLE for any role that hasn't been customized
    /// @dev OZ AccessControl default: every role is administered by DEFAULT_ADMIN_ROLE unless overridden
    function test_getRoleAdmin_success_defaultsToAdminRole(bytes32 role) public {
        // unimplemented
    }

    /// @notice Verifies getRoleAdmin returns the new admin role after setRoleAdmin
    /// @dev Read-after-write for role-admin reassignment
    function test_getRoleAdmin_success_reflectsSetRoleAdmin(bytes32 role, bytes32 newAdminRole) public {
        // unimplemented
    }
}
