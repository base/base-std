// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

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
        token.renounceRole(B20Constants.DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Verifies a non-admin's renounceRole(DEFAULT_ADMIN_ROLE, self) is a silent no-op
    ///         even when the token has exactly one admin (regression test for L-03)
    /// @dev IB20.renounceRole NatSpec: "reverts with LastAdminCannotRenounce when the caller
    ///      is the sole remaining admin." A non-admin caller is NOT the sole remaining admin
    ///      and MUST NOT trigger that revert. The correct path: `_revokeRole` checks the
    ///      caller's role bit and silently no-ops for non-holders. A buggy guard that fires
    ///      on `adminCount == 1` alone (without checking `hasRole(DEFAULT_ADMIN_ROLE, caller)`)
    ///      would block defensive batches and mislead Rust implementers copying the pattern.
    function test_renounceRole_success_nonAdminRenounceIsNoOp(address nonAdmin) public {
        _assumeValidActor(nonAdmin);
        vm.assume(nonAdmin != admin);

        // Precondition: nonAdmin doesn't hold the role and there is exactly one admin.
        assertFalse(
            token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, nonAdmin), "precondition: nonAdmin must not be admin"
        );
        assertTrue(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin), "precondition: admin must be admin");

        // Should succeed silently — caller doesn't hold the role, so _revokeRole no-ops.
        vm.prank(nonAdmin);
        token.renounceRole(B20Constants.DEFAULT_ADMIN_ROLE, nonAdmin);

        // Postconditions: nothing changed.
        assertFalse(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, nonAdmin), "nonAdmin still doesn't hold admin role");
        assertTrue(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin), "admin still holds admin role");
    }

    /// @notice Verifies renounceRole sets hasRole(role, caller) to false
    /// @dev Read-after-write for self-revocation.
    ///      Paired slot assertion: `roles[role][caller]` slot is zero.
    function test_renounceRole_success_clearsCallerRole(address caller, bytes32 role) public {
        _assumeValidCaller(caller);
        // Skip DEFAULT_ADMIN_ROLE here: that path has its own last-admin guard tested above
        // and an "admin with others" success test below.
        vm.assume(role != B20Constants.DEFAULT_ADMIN_ROLE);

        _grantRole(role, caller);
        assertTrue(token.hasRole(role, caller), "precondition");

        vm.prank(caller);
        token.renounceRole(role, caller);
        assertFalse(token.hasRole(role, caller), "role must be cleared after self-renounce");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.roleMembershipSlot(role, caller))),
            uint256(0),
            "roles[role][caller] slot must be cleared after self-renounce"
        );
    }

    /// @notice Verifies renounceRole succeeds for DEFAULT_ADMIN_ROLE when at least one other admin exists
    /// @dev LastAdminCannotRenounce only fires when the renouncer would leave the role empty.
    ///      Paired slot assertions verify both `roles[ADMIN][admin]`
    ///      (cleared) and `roles[ADMIN][otherAdmin]` (still set), plus
    ///      the `adminCount` slot decrements from 2 to 1 while the
    ///      `initialized` slot stays true. `adminCount` and `initialized`
    ///      now live in disjoint slots (slot 8 and slot 14 respectively),
    ///      so each is asserted with its own `vm.load`.
    function test_renounceRole_success_adminWithOthers(address otherAdmin) public {
        _assumeValidActor(otherAdmin);
        vm.assume(otherAdmin != admin);

        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin);

        vm.prank(admin);
        token.renounceRole(B20Constants.DEFAULT_ADMIN_ROLE, admin);

        assertFalse(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin), "original admin no longer admin");
        assertTrue(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin), "other admin still admin");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.roleMembershipSlot(B20Constants.DEFAULT_ADMIN_ROLE, admin))),
            uint256(0),
            "roles[ADMIN][admin] slot must be cleared"
        );
        assertEq(
            uint256(
                vm.load(address(token), MockB20Storage.roleMembershipSlot(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin))
            ),
            uint256(1),
            "roles[ADMIN][otherAdmin] slot must still be set"
        );
        assertEq(uint256(vm.load(address(token), MockB20Storage.adminCountSlot())), 1, "adminCount must drop to 1");
        _assertInitialized(address(token), "initialized marker must stay set");
    }

    /// @notice Verifies the internal adminCount tracker stays consistent with role state
    /// @dev We can't read adminCount directly (it's internal storage), so we verify it
    ///      indirectly: after one of two admins renounces, the SOLE remaining admin's
    ///      own renounceRole should now trip the last-admin guard. A buggy impl that
    ///      mis-tracked adminCount (e.g. incrementing on revoke instead of decrementing)
    ///      would let the remaining admin renounce silently, bricking the token without
    ///      surfacing the bug.
    function test_renounceRole_success_adminCountStaysConsistent(address otherAdmin) public {
        _assumeValidActor(otherAdmin);
        vm.assume(otherAdmin != admin);

        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin);

        vm.prank(admin);
        token.renounceRole(B20Constants.DEFAULT_ADMIN_ROLE, admin);

        vm.prank(otherAdmin);
        vm.expectRevert(IB20.LastAdminCannotRenounce.selector);
        token.renounceRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin);
    }

    /// @notice Verifies renounceRole emits RoleRevoked(role, caller, caller)
    /// @dev Sender equals account for self-revocation; canonical RoleRevoked test lives in revokeRole.t.sol
    function test_renounceRole_success_emitsRoleRevoked(address caller, bytes32 role) public {
        _assumeValidCaller(caller);
        vm.assume(role != B20Constants.DEFAULT_ADMIN_ROLE);

        _grantRole(role, caller);

        vm.expectEmit(true, true, true, false, address(token));
        emit IB20.RoleRevoked(role, caller, caller);
        vm.prank(caller);
        token.renounceRole(role, caller);
    }
}
