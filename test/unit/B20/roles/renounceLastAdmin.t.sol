// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20RenounceLastAdminTest is B20Test {
    /// @notice Verifies renounceLastAdmin reverts when caller does not hold DEFAULT_ADMIN_ROLE
    /// @dev    Distinct from NotSoleAdmin: the caller isn't an admin at all,
    ///         so authorization fails before the "are you the only one?" check.
    ///         Checks AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE).
    function test_renounceLastAdmin_revert_callerNotAdmin(address caller) public {
        // unimplemented
    }

    /// @notice Verifies renounceLastAdmin reverts when caller is an admin but additional admins exist
    /// @dev    The function exists exclusively to transition single-admin → zero-admin.
    ///         Callers that want to step away while leaving the token administered should
    ///         use renounceRole (which only allows non-last admins to renounce themselves).
    ///         Checks NotSoleAdmin() error.
    function test_renounceLastAdmin_revert_multipleAdmins(address otherAdmin) public {
        // unimplemented
    }

    /// @notice Verifies renounceLastAdmin clears DEFAULT_ADMIN_ROLE from the caller
    /// @dev    Read-after-write: hasRole(DEFAULT_ADMIN_ROLE, msg.sender) is false post-call.
    function test_renounceLastAdmin_success_clearsAdminRole() public {
        // unimplemented
    }

    /// @notice Verifies admin-gated operations revert after renounceLastAdmin
    /// @dev    Permanent-immutability invariant. updatePolicy is the canonical example;
    ///         the same mechanism (no admin holder → AccessControlUnauthorizedAccount on
    ///         any DEFAULT_ADMIN_ROLE-gated call) covers setSupplyCap, setContractURI,
    ///         setName, setSymbol, grantRole / revokeRole / setRoleAdmin for any role.
    ///         No test should be able to reinstate an admin after this transition.
    function test_renounceLastAdmin_success_subsequentAdminCallsRevert(bytes32 policyType, uint64 newPolicyId) public {
        // unimplemented
    }

    /// @notice Verifies grantRole(DEFAULT_ADMIN_ROLE, ...) cannot succeed post-renunciation
    /// @dev    Explicit test of the "no path back to admin" property. grantRole requires
    ///         the caller to hold the admin role for the target role; with zero admins,
    ///         every grant call (from any caller, for any account) reverts.
    function test_renounceLastAdmin_success_noPathToReinstateAdmin(address wouldBeNewAdmin, address caller) public {
        // unimplemented
    }

    /// @notice Verifies renounceLastAdmin emits LastAdminRenounced(previousAdmin)
    /// @dev    Canonical emission test for LastAdminRenounced. The standard
    ///         RoleRevoked(DEFAULT_ADMIN_ROLE, caller, caller) is also emitted, but its
    ///         canonical emission test lives in revokeRole.t.sol; this stub asserts
    ///         only the dedicated event.
    function test_renounceLastAdmin_success_emitsLastAdminRenounced() public {
        // unimplemented
    }
}
