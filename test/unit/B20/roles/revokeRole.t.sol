// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20RevokeRoleTest is B20Test {
    /// @notice Verifies revokeRole reverts when caller does not hold the role's admin role
    /// @dev Access control: caller must hold getRoleAdmin(role); checks AccessControlUnauthorizedAccount
    function test_revokeRole_revert_unauthorized(address caller, bytes32 role, address account) public {
        // unimplemented
    }

    /// @notice Verifies revokeRole sets hasRole(role, account) to false
    /// @dev Read-after-write; canonical hasRole readback test lives in hasRole.t.sol
    function test_revokeRole_success_clearsRole(bytes32 role, address account) public {
        // unimplemented
    }

    /// @notice Verifies revokeRole is idempotent when the account does not hold the role
    /// @dev No-op for not-held accounts; no revert, no duplicate event
    function test_revokeRole_success_idempotent(bytes32 role, address account) public {
        // unimplemented
    }

    /// @notice Verifies revokeRole emits RoleRevoked(role, account, sender) when an actual revoke occurs
    /// @dev Event integrity; canonical RoleRevoked emission test
    function test_revokeRole_success_emitsRoleRevoked(bytes32 role, address account) public {
        // unimplemented
    }
}
