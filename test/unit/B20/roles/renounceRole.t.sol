// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20RenounceRoleTest is B20Test {
    /// @notice Verifies renounceRole reverts when callerConfirmation does not equal msg.sender
    /// @dev Fat-finger guard: caller must explicitly confirm; OZ-style invariant
    function test_renounceRole_revert_callerConfirmationMismatch(
        address caller,
        bytes32 role,
        address wrongConfirmation
    ) public {
        _assumeValidCaller(caller);
        vm.assume(wrongConfirmation != caller);

        vm.prank(caller);
        vm.expectRevert(IB20.AccessControlBadConfirmation.selector);
        token.renounceRole(role, wrongConfirmation);
    }

    /// @notice Verifies renounceRole reverts when the caller is the last DEFAULT_ADMIN_ROLE holder
    /// @dev Tokens MUST always have at least one admin; checks LastAdminCannotRenounce() error
    function test_renounceRole_revert_lastAdminCannotRenounce() public {
        // Bootstrap admin is the only admin (adminCount == 1).
        vm.prank(admin);
        vm.expectRevert(IB20.LastAdminCannotRenounce.selector);
        token.renounceRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Verifies renounceRole sets hasRole(role, caller) to false
    /// @dev Read-after-write for self-revocation
    function test_renounceRole_success_clearsCallerRole(address caller, bytes32 role) public {
        _assumeValidCaller(caller);
        // Skip DEFAULT_ADMIN_ROLE here: that path has its own last-admin guard tested above
        // and an "admin with others" success test below.
        vm.assume(role != DEFAULT_ADMIN_ROLE);

        _grantRole(role, caller);
        assertTrue(token.hasRole(role, caller), "precondition");

        vm.prank(caller);
        token.renounceRole(role, caller);
        assertFalse(token.hasRole(role, caller), "role must be cleared after self-renounce");
    }

    /// @notice Verifies renounceRole succeeds for DEFAULT_ADMIN_ROLE when at least one other admin exists
    /// @dev LastAdminCannotRenounce only fires when the renouncer would leave the role empty
    function test_renounceRole_success_adminWithOthers(address otherAdmin) public {
        _assumeValidActor(otherAdmin);
        vm.assume(otherAdmin != admin);

        _grantRole(DEFAULT_ADMIN_ROLE, otherAdmin);

        vm.prank(admin);
        token.renounceRole(DEFAULT_ADMIN_ROLE, admin);

        assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin), "original admin no longer admin");
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, otherAdmin), "other admin still admin");
    }

    /// @notice Verifies renounceRole emits RoleRevoked(role, caller, caller)
    /// @dev Sender equals account for self-revocation; canonical RoleRevoked test lives in revokeRole.t.sol
    function test_renounceRole_success_emitsRoleRevoked(address caller, bytes32 role) public {
        _assumeValidCaller(caller);
        vm.assume(role != DEFAULT_ADMIN_ROLE);

        _grantRole(role, caller);

        vm.expectEmit(true, true, true, false, address(token));
        emit IB20.RoleRevoked(role, caller, caller);
        vm.prank(caller);
        token.renounceRole(role, caller);
    }
}
