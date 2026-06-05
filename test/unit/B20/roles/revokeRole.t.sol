// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20RevokeRoleTest is B20Test {
    /// @notice Verifies revokeRole reverts when caller does not hold the role's admin role
    /// @dev Access control: caller must hold getRoleAdmin(role); checks AccessControlUnauthorizedAccount
    function test_revokeRole_revert_unauthorized(address caller, bytes32 role, address account) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.revokeRole(role, account);
    }

    /// @notice Verifies revokeRole reverts when the call would remove the sole DEFAULT_ADMIN_ROLE holder
    /// @dev Without this guard, `revokeRole(DEFAULT_ADMIN_ROLE, soleAdmin)` would
    ///      succeed silently, bricking the token: admin operations become unreachable, and no
    ///      `LastAdminRenounced` event is emitted to signal the terminal state. The dedicated
    ///      `renounceLastAdmin()` path remains the only legitimate way to remove the final admin.
    ///      Reverts with `LastAdminCannotRenounce` (reused from the renounceRole guard — same
    ///      invariant: the last admin can only be removed via the explicit
    ///      `renounceLastAdmin` path).
    function test_revokeRole_revert_lastAdmin() public {
        assertEq(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin), true, "precondition: admin is the sole admin");

        vm.prank(admin);
        vm.expectRevert(IB20.LastAdminCannotRenounce.selector);
        token.revokeRole(B20Constants.DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Verifies revokeRole sets hasRole(role, account) to false
    /// @dev Read-after-write; canonical hasRole readback test lives in hasRole.t.sol.
    ///      Skips revoking DEFAULT_ADMIN_ROLE from the sole bootstrap admin
    ///      (would revert with LastAdminCannotRenounce per the last-admin guard;
    ///      see test_revokeRole_revert_lastAdmin and renounceLastAdmin.t.sol
    ///      for the terminal-admin removal path).
    ///      Paired slot assertion: the `roles[role][account]` slot
    ///      reads back as zero after the revoke.
    function test_revokeRole_success_clearsRole(bytes32 role, address account) public {
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));
        _grantRole(role, account);

        vm.prank(admin);
        token.revokeRole(role, account);
        assertFalse(token.hasRole(role, account), "role must be cleared after revoke");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.roleMembershipSlot(role, account))),
            uint256(0),
            "roles[role][account] slot must be cleared after revoke"
        );
    }

    /// @notice Verifies revokeRole successfully removes a non-sole admin
    /// @dev With multiple admins, revoking one is permitted because adminCount stays >= 1
    ///      and the token remains operable. Complements test_revokeRole_revert_lastAdmin
    ///      which proves the guard only fires when the count would drop to zero.
    function test_revokeRole_success_revokesNonSoleAdmin(address otherAdmin) public {
        _assumeValidActor(otherAdmin);
        vm.assume(otherAdmin != admin);
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin);
        assertEq(uint256(vm.load(address(token), MockB20Storage.adminCountSlot())), 2, "precondition: two admins exist");

        vm.prank(admin);
        token.revokeRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin);

        assertFalse(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin), "otherAdmin must lose admin role");
        assertTrue(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin), "original admin retains role");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.adminCountSlot())), 1, "adminCount must drop from 2 to 1"
        );
    }

    /// @notice Verifies revokeRole is idempotent when the account does not hold the role
    /// @dev No-op for not-held accounts; no revert (including for the
    ///      DEFAULT_ADMIN_ROLE-on-non-holder case, since the last-admin guard only
    ///      fires when the target ACTUALLY holds the role), no duplicate event.
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
