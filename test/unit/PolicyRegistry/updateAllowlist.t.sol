// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryUpdateAllowlistTest is PolicyRegistryTest {
    /// @notice Verifies updateAllowlist reverts when called by any non-admin caller
    /// @dev Access control: only the current admin may mutate membership; checks Unauthorized() error
    function test_updateAllowlist_revert_unauthorized(address caller, bool allowed, address[] memory accounts) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        accounts = _boundAccounts(accounts);
        uint64 policyId = _createAllowlist();
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.updateAllowlist(policyId, allowed, accounts);
    }

    /// @notice Verifies updateAllowlist reverts when invoked on a BLOCKLIST policy
    /// @dev Type guard: each update function only operates on its own policy type; checks IncompatiblePolicyType()
    function test_updateAllowlist_revert_incompatiblePolicyType(
        address currentAdmin,
        bool allowed,
        address[] memory accounts
    ) public {
        vm.assume(currentAdmin != address(0));
        accounts = _boundAccounts(accounts);
        uint64 policyId = _createBlocklist(admin, currentAdmin);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, allowed, accounts);
    }

    /// @notice Verifies updateAllowlist reverts for an unknown policy id
    /// @dev Built-ins and unknown ids cannot be mutated; checks PolicyNotFound() error
    function test_updateAllowlist_revert_policyNotFound(
        address caller,
        uint64 policyId,
        bool allowed,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(policyId > 1);
        accounts = _boundAccounts(accounts);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.updateAllowlist(policyId, allowed, accounts);
    }

    /// @notice Verifies updateAllowlist(allowed = true) adds each account to the membership set
    /// @dev isAuthorized returns true for each added account afterward.
    ///      Paired slot assertion: each `members[id][account]` slot
    ///      reads back as 1.
    function test_updateAllowlist_success_addsAccounts(address currentAdmin, address[] memory accounts) public {
        vm.assume(currentAdmin != address(0));
        accounts = _boundAccounts(accounts);
        uint64 policyId = _createAllowlist(admin, currentAdmin);
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, true, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertTrue(policyRegistry.isAuthorized(policyId, accounts[i]));
            assertEq(
                uint256(
                    vm.load(address(policyRegistry), MockPolicyRegistryStorage.policyMemberSlot(policyId, accounts[i]))
                ),
                uint256(1),
                "members[id][account] slot must be set after allowed=true"
            );
        }
    }

    /// @notice Verifies updateAllowlist(allowed = false) removes each account from the membership set
    /// @dev isAuthorized returns false for each removed account afterward.
    ///      Paired slot assertion: each `members[id][account]` slot
    ///      reads back as 0.
    function test_updateAllowlist_success_removesAccounts(address currentAdmin, address[] memory accounts) public {
        vm.assume(currentAdmin != address(0));
        accounts = _boundAccounts(accounts);
        uint64 policyId = _createAllowlist(admin, currentAdmin);
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, true, accounts);
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, false, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertFalse(policyRegistry.isAuthorized(policyId, accounts[i]));
            assertEq(
                uint256(
                    vm.load(address(policyRegistry), MockPolicyRegistryStorage.policyMemberSlot(policyId, accounts[i]))
                ),
                uint256(0),
                "members[id][account] slot must be cleared after allowed=false"
            );
        }
    }

    /// @notice Verifies duplicate accounts within a single call are idempotent
    /// @dev Repeated entries do not change the final membership state
    function test_updateAllowlist_success_idempotentDuplicates(address currentAdmin, address account) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = _createAllowlist(admin, currentAdmin);
        address[] memory duped = new address[](2);
        duped[0] = account;
        duped[1] = account;
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, true, duped);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, false, duped);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies updateAllowlist emits a single AllowlistUpdated carrying the full batch
    /// @dev One event per call, regardless of batch size; topic args match policyId / updater / allowed
    function test_updateAllowlist_success_emitsAllowlistUpdated(
        address currentAdmin,
        bool allowed,
        address[] memory accounts
    ) public {
        vm.assume(currentAdmin != address(0));
        accounts = _boundAccounts(accounts);
        uint64 policyId = _createAllowlist(admin, currentAdmin);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.AllowlistUpdated(policyId, currentAdmin, allowed, accounts);
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, allowed, accounts);
    }

    /// @notice Verifies updateAllowlist reverts when the batch exceeds MAX_BATCH_SIZE
    /// @dev Mirrors the Rust precompile's batch limit; checks
    ///      BatchSizeTooLarge(maxBatchSize). Fuzz drives `overflow` so the test exercises
    ///      arbitrary over-the-limit sizes.
    function test_updateAllowlist_revert_batchSizeTooLarge(address currentAdmin, bool allowed, uint8 overflow) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = _createAllowlist(admin, currentAdmin);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, allowed, accounts);
    }

    /// @notice Verifies updateAllowlist accepts a batch exactly at MAX_BATCH_SIZE
    /// @dev Boundary check: the limit is inclusive.
    function test_updateAllowlist_success_batchAtLimit(address currentAdmin, bool allowed) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = _createAllowlist(admin, currentAdmin);
        address[] memory accounts = _makeAccounts(MAX_BATCH_SIZE);
        vm.prank(currentAdmin);
        policyRegistry.updateAllowlist(policyId, allowed, accounts);
        assertTrue(policyRegistry.policyExists(policyId));
    }
}
