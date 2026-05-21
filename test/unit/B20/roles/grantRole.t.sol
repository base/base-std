// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

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
}
