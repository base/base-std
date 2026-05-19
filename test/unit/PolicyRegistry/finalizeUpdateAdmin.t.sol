// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryFinalizeUpdateAdminTest is PolicyRegistryTest {
    /// @notice Verifies finalizeUpdateAdmin reverts when no admin transfer is in flight
    /// @dev Pending-slot precondition; checks NoPendingAdmin() error
    function test_finalizeUpdateAdmin_revert_noPendingAdmin(address caller) public {
        // unimplemented
    }

    /// @notice Verifies finalizeUpdateAdmin reverts for callers other than the staged pending admin
    /// @dev Access control: only the pending admin can claim; checks Unauthorized() error
    function test_finalizeUpdateAdmin_revert_unauthorized(address pending, address caller) public {
        // unimplemented
    }

    /// @notice Verifies finalizeUpdateAdmin reverts for an unknown policy id
    /// @dev Built-ins and unknown ids are not administrable; checks PolicyNotFound() error
    function test_finalizeUpdateAdmin_revert_policyNotFound(address caller, uint64 policyId) public {
        // unimplemented
    }

    /// @notice Verifies finalizeUpdateAdmin promotes the pending admin to current admin
    /// @dev policyAdmin returns the previously-staged address after this call
    function test_finalizeUpdateAdmin_success_promotesPending(address currentAdmin, address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies finalizeUpdateAdmin clears the pending slot
    /// @dev pendingPolicyAdmin returns address(0) after the transfer completes
    function test_finalizeUpdateAdmin_success_clearsPending(address currentAdmin, address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies finalizeUpdateAdmin emits PolicyAdminUpdated with previousAdmin and newAdmin
    /// @dev Canonical PolicyAdminUpdated event test; other emission paths (create / renounce) are
    ///      tested in their own files because their args differ (previousAdmin = 0 / newAdmin = 0)
    function test_finalizeUpdateAdmin_success_emitsPolicyAdminUpdated(address currentAdmin, address newAdmin) public {
        // unimplemented
    }
}
