// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20HasRoleTest is B20Test {
    /// @notice Verifies hasRole returns false for any (role, account) pair that has never been granted
    /// @dev Default state across the role and address space. Filters out the bootstrap admin grant
    ///      (DEFAULT_ADMIN_ROLE, admin) since that pair IS held after creation.
    function test_hasRole_success_falseByDefault(bytes32 role, address account) public view {
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));
        assertFalse(token.hasRole(role, account), "untouched (role, account) pair must be unheld");
    }

    /// @notice Verifies hasRole returns true after grantRole succeeds
    /// @dev Read-after-write for the role mapping
    function test_hasRole_success_trueAfterGrant(bytes32 role, address account) public {
        _grantRole(role, account);
        assertTrue(token.hasRole(role, account), "must be held after grant");
    }

    /// @notice Verifies hasRole returns false after revokeRole succeeds
    /// @dev Read-after-write for revocation. Skips revoking DEFAULT_ADMIN_ROLE from the sole
    ///      admin (which would underflow adminCount semantics via revoke; the user must use
    ///      renounceLastAdmin for that transition, covered elsewhere).
    function test_hasRole_success_falseAfterRevoke(bytes32 role, address account) public {
        vm.assume(!(role == B20Constants.DEFAULT_ADMIN_ROLE && account == admin));
        _grantRole(role, account);
        vm.prank(admin);
        token.revokeRole(role, account);
        assertFalse(token.hasRole(role, account), "must be unheld after revoke");
    }
}
