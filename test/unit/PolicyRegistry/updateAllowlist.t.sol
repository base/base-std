// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryUpdateAllowlistTest is PolicyRegistryTest {
    /// @notice Verifies updateAllowlist reverts when called by any non-admin caller
    /// @dev Access control: only the current admin may mutate membership; checks Unauthorized() error
    function test_updateAllowlist_revert_unauthorized(address caller, bool allowed, address[] memory accounts) public {
        // unimplemented
    }

    /// @notice Verifies updateAllowlist reverts when invoked on a BLOCKLIST policy
    /// @dev Type guard: each update function only operates on its own policy type; checks IncompatiblePolicyType()
    function test_updateAllowlist_revert_incompatiblePolicyType(
        address currentAdmin,
        bool allowed,
        address[] memory accounts
    ) public {
        // unimplemented
    }

    /// @notice Verifies updateAllowlist reverts for an unknown policy id
    /// @dev Built-ins and unknown ids cannot be mutated; checks PolicyNotFound() error
    function test_updateAllowlist_revert_policyNotFound(
        address caller,
        uint64 policyId,
        bool allowed,
        address[] memory accounts
    ) public {
        // unimplemented
    }

    /// @notice Verifies updateAllowlist(allowed = true) adds each account to the membership set
    /// @dev isAuthorized returns true for each added account afterward
    function test_updateAllowlist_success_addsAccounts(address currentAdmin, address[] memory accounts) public {
        // unimplemented
    }

    /// @notice Verifies updateAllowlist(allowed = false) removes each account from the membership set
    /// @dev isAuthorized returns false for each removed account afterward
    function test_updateAllowlist_success_removesAccounts(address currentAdmin, address[] memory accounts) public {
        // unimplemented
    }

    /// @notice Verifies duplicate accounts within a single call are idempotent
    /// @dev Repeated entries do not change the final membership state
    function test_updateAllowlist_success_idempotentDuplicates(address currentAdmin, address[] memory accounts)
        public
    {
        // unimplemented
    }

    /// @notice Verifies updateAllowlist emits a single AllowlistUpdated carrying the full batch
    /// @dev One event per call, regardless of batch size; topic args match policyId / updater / allowed
    function test_updateAllowlist_success_emitsAllowlistUpdated(
        address currentAdmin,
        bool allowed,
        address[] memory accounts
    ) public {
        // unimplemented
    }
}
