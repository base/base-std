// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20GrantRoleTest is B20Test {
    /// @notice Verifies grantRole reverts when caller does not hold the role's admin role
    /// @dev Access control: caller must hold getRoleAdmin(role); checks AccessControlUnauthorizedAccount.
    ///      All roles default to DEFAULT_ADMIN_ROLE as their admin, so a non-admin caller hits
    ///      AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE).
    function test_grantRole_revert_unauthorized(address caller, bytes32 role, address account) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.grantRole(role, account);
    }

    /// @notice Verifies grantRole sets hasRole(role, account) to true
    /// @dev Read-after-write; canonical hasRole readback test lives in hasRole.t.sol.
    ///      Paired slot assertion: the `roles[role][account]` bool slot
    ///      holds `bytes32(uint256(1))` after the grant.
    function test_grantRole_success_setsRole(bytes32 role, address account) public {
        _grantRole(role, account);
        assertTrue(token.hasRole(role, account), "must hold role after grant");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.roleMembershipSlot(role, account))),
            uint256(1),
            "roles[role][account] slot must hold the membership flag"
        );
    }

    /// @notice Verifies grantRole is idempotent when the account already holds the role
    /// @dev No-op for already-granted accounts; no revert, no duplicate event.
    ///      We use vm.recordLogs to assert that the second grant emits NO RoleGranted event.
    function test_grantRole_success_idempotent(bytes32 role, address account) public {
        _grantRole(role, account);
        assertTrue(token.hasRole(role, account), "precondition: role held after first grant");

        vm.recordLogs();
        _grantRole(role, account);
        assertTrue(token.hasRole(role, account), "role still held after second grant");

        // The recorded logs should be empty: idempotent path skips the RoleGranted emit.
        assertEq(vm.getRecordedLogs().length, 0, "idempotent grant must not emit RoleGranted");
    }

    /// @notice Verifies grantRole emits RoleGranted(role, account, sender) on first grant
    /// @dev Event integrity; canonical RoleGranted emission test
    function test_grantRole_success_emitsRoleGranted(bytes32 role, address account) public {
        // Filter the bootstrap admin grant (already held, idempotent → no emit).
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));

        vm.expectEmit(true, true, true, false, address(token));
        emit IB20.RoleGranted(role, account, admin);
        _grantRole(role, account);
    }

    /// @notice Verifies grantRole reverts on an admin-less token even when the caller holds a
    ///         custom-admin role that would otherwise authorize the grant.
    /// @dev Admin-role-resurrection guard — mirrors the Rust precompile's
    ///      `ensure_role_admin_mutations_available`. Without this guard a custom-admin
    ///      role chain set up while an admin existed (e.g. setRoleAdmin(MINT_ROLE, BURN_ROLE)
    ///      + grantRole(BURN_ROLE, alice)) survives `renounceLastAdmin()` and lets BURN_ROLE
    ///      holders keep mutating the role graph on a token that has no admin. The shared
    ///      `onlyRoleAdmin` modifier short-circuits when adminCount == 0 with
    ///      `AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE)`, matching Rust.
    ///
    ///      Same guard fires on `revokeRole` and `setRoleAdmin` (also `onlyRoleAdmin`-gated);
    ///      this test pins the property at the modifier level via the grantRole entry.
    function test_grantRole_revert_adminResurrectionViaCustomChain(address customAdmin, address recipient) public {
        _assumeValidActor(customAdmin);
        _assumeValidActor(recipient);
        vm.assume(customAdmin != admin);
        vm.assume(recipient != admin);
        vm.assume(customAdmin != recipient);

        // 1. admin makes BURN_ROLE the admin-of MINT_ROLE.
        vm.prank(admin);
        token.setRoleAdmin(B20Constants.MINT_ROLE, B20Constants.BURN_ROLE);

        // 2. admin grants BURN_ROLE to customAdmin so they become an admin-of-MINT_ROLE.
        _grantRole(B20Constants.BURN_ROLE, customAdmin);

        // 3. admin renounces the last admin — adminCount drops to 0.
        vm.prank(admin);
        token.renounceLastAdmin();
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.adminCountSlot())), 0, "precondition: token is admin-less"
        );
        assertTrue(
            token.hasRole(B20Constants.BURN_ROLE, customAdmin), "precondition: custom-chain admin still holds BURN_ROLE"
        );

        // 4. customAdmin attempts to mutate the role graph. The shared `onlyRoleAdmin`
        //    modifier rejects with DEFAULT_ADMIN_ROLE as the needed-role payload — matching
        //    Rust's `ensure_role_admin_mutations_available`.
        vm.prank(customAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, customAdmin, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.grantRole(B20Constants.MINT_ROLE, recipient);
    }
}
