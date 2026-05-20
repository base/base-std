// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryUpdateBlocklistTest is PolicyRegistryTest {
    /// @notice Verifies updateBlocklist reverts when called by any non-admin caller
    /// @dev Access control: only the current admin may mutate membership; checks Unauthorized() error
    function test_updateBlocklist_revert_unauthorized(address caller, bool blocked, address[] memory accounts) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.updateBlocklist(policyId, blocked, accounts);
    }

    /// @notice Verifies updateBlocklist reverts when invoked on an ALLOWLIST policy
    /// @dev Type guard: each update function only operates on its own policy type; checks IncompatiblePolicyType()
    function test_updateBlocklist_revert_incompatiblePolicyType(
        address currentAdmin,
        bool blocked,
        address[] memory accounts
    ) public {
        vm.assume(currentAdmin != address(0));
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, blocked, accounts);
    }

    /// @notice Verifies updateBlocklist reverts for an unknown policy id
    /// @dev Built-ins and unknown ids cannot be mutated; checks PolicyNotFound() error
    function test_updateBlocklist_revert_policyNotFound(
        address caller,
        uint64 policyId,
        bool blocked,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(policyId > 1);
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.updateBlocklist(policyId, blocked, accounts);
    }

    /// @notice Verifies updateBlocklist(blocked = true) adds each account to the membership set
    /// @dev isAuthorized returns false for each added account afterward
    function test_updateBlocklist_success_addsAccounts(address currentAdmin, address[] memory accounts) public {
        vm.assume(currentAdmin != address(0));
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, true, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertFalse(policyRegistry.isAuthorized(policyId, accounts[i]));
        }
    }

    /// @notice Verifies updateBlocklist(blocked = false) removes each account from the membership set
    /// @dev isAuthorized returns true for each removed account afterward
    function test_updateBlocklist_success_removesAccounts(address currentAdmin, address[] memory accounts) public {
        vm.assume(currentAdmin != address(0));
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, true, accounts);
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, false, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertTrue(policyRegistry.isAuthorized(policyId, accounts[i]));
        }
    }

    /// @notice Verifies duplicate accounts within a single call are idempotent
    /// @dev Repeated entries do not change the final membership state
    function test_updateBlocklist_success_idempotentDuplicates(address currentAdmin, address account) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.BLOCKLIST);
        address[] memory duped = new address[](2);
        duped[0] = account;
        duped[1] = account;
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, true, duped);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, false, duped);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies updateBlocklist emits a single BlocklistUpdated carrying the full batch
    /// @dev One event per call, regardless of batch size; topic args match policyId / updater / blocked
    function test_updateBlocklist_success_emitsBlocklistUpdated(
        address currentAdmin,
        bool blocked,
        address[] memory accounts
    ) public {
        vm.assume(currentAdmin != address(0));
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.BlocklistUpdated(policyId, currentAdmin, blocked, accounts);
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, blocked, accounts);
    }
}
