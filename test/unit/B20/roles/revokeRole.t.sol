// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

contract B20RevokeRoleTest is B20Test {
    /// @notice Verifies revokeRole reverts when caller does not hold the role's admin role
    /// @dev Access control: caller must hold getRoleAdmin(role); checks AccessControlUnauthorizedAccount
    function test_revokeRole_revert_unauthorized(address caller, bytes32 role, address account) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE)
        );
        token.revokeRole(role, account);
    }

    /// @notice Verifies revokeRole sets hasRole(role, account) to false
    /// @dev Read-after-write; canonical hasRole readback test lives in hasRole.t.sol.
    ///      Skips revoking DEFAULT_ADMIN_ROLE from the sole bootstrap admin
    ///      (would require renounceLastAdmin instead, covered in that file).
    function test_revokeRole_success_clearsRole(bytes32 role, address account) public {
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));
        _grantRole(role, account);

        vm.prank(admin);
        token.revokeRole(role, account);
        assertFalse(token.hasRole(role, account), "role must be cleared after revoke");
    }

    /// @notice Verifies revokeRole is idempotent when the account does not hold the role
    /// @dev No-op for not-held accounts; no revert, no duplicate event.
    function test_revokeRole_success_idempotent(bytes32 role, address account) public {
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));
        assertFalse(token.hasRole(role, account), "precondition: role not held");

        vm.recordLogs();
        vm.prank(admin);
        token.revokeRole(role, account);
        assertFalse(token.hasRole(role, account), "role still not held");

        assertEq(vm.getRecordedLogs().length, 0, "idempotent revoke must not emit RoleRevoked");
    }

    /// @notice Verifies revokeRole emits RoleRevoked(role, account, sender) when an actual revoke occurs
    /// @dev Event integrity; canonical RoleRevoked emission test
    function test_revokeRole_success_emitsRoleRevoked(bytes32 role, address account) public {
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));
        _grantRole(role, account);

        vm.expectEmit(true, true, true, false, address(token));
        emit IB20.RoleRevoked(role, account, admin);
        vm.prank(admin);
        token.revokeRole(role, account);
    }
}
