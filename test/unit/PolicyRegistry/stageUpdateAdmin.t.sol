// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryStageUpdateAdminTest is PolicyRegistryTest {
    /// @notice Verifies stageUpdateAdmin reverts when called by any non-admin caller
    /// @dev Access control: only the current admin may stage a transfer; checks Unauthorized() error
    function test_stageUpdateAdmin_revert_unauthorized(address caller, address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies stageUpdateAdmin reverts for an unknown policy id
    /// @dev Built-ins and unknown ids are not administrable; checks PolicyNotFound() error
    function test_stageUpdateAdmin_revert_policyNotFound(address caller, uint64 policyId, address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies stageUpdateAdmin sets pendingPolicyAdmin to the nominated address
    /// @dev Pending slot updated; current admin unchanged until finalizeUpdateAdmin
    function test_stageUpdateAdmin_success_setsPending(address currentAdmin, address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies a second stageUpdateAdmin overwrites a previously-staged candidate
    /// @dev Latest call wins; the prior candidate loses ability to finalize
    function test_stageUpdateAdmin_success_overwritesPrior(address currentAdmin, address first, address second)
        public
    {
        // unimplemented
    }

    /// @notice Verifies stageUpdateAdmin(address(0)) clears a previously-staged candidate
    /// @dev Explicit cancel path; pendingPolicyAdmin returns address(0) after
    function test_stageUpdateAdmin_success_clearsPending(address currentAdmin, address first) public {
        // unimplemented
    }

    /// @notice Verifies stageUpdateAdmin emits PolicyAdminStaged with the correct args
    /// @dev Event integrity: policyId, currentAdmin, pendingAdmin match the call
    function test_stageUpdateAdmin_success_emitsPolicyAdminStaged(address currentAdmin, address newAdmin) public {
        // unimplemented
    }
}
