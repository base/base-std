// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryCreatePolicyWithAccountsTest is PolicyRegistryTest {
    /// @notice Verifies createPolicyWithAccounts reverts when admin is the zero address
    /// @dev Required-field guard; checks ZeroAddress() error
    function test_createPolicyWithAccounts_revert_zeroAdmin(address caller, address[] memory accounts) public {
        _assumeValidCaller(caller);
        accounts = _boundAccounts(accounts);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(address(0), IPolicyRegistry.PolicyType.ALLOWLIST, accounts);
    }

    /// @notice Verifies createPolicyWithAccounts seeds an allowlist policy with the provided members
    /// @dev Post-creation isAuthorized returns true for each seeded account.
    ///      Paired slot assertion: each `members[id][account]` slot
    ///      reads back as 1 (membership flag set).
    function test_createPolicyWithAccounts_success_seedsAllowlist(
        address caller,
        address admin_,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        accounts = _boundAccounts(accounts);
        vm.prank(caller);
        uint64 policyId =
            policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertTrue(policyRegistry.isAuthorized(policyId, accounts[i]));
            assertEq(
                uint256(
                    vm.load(address(policyRegistry), MockPolicyRegistryStorage.policyMemberSlot(policyId, accounts[i]))
                ),
                uint256(1),
                "members[id][account] slot must be set after allowlist seed"
            );
        }
    }

    /// @notice Verifies createPolicyWithAccounts seeds a blocklist policy with the provided members
    /// @dev Post-creation isAuthorized returns false for each seeded account.
    ///      Paired slot assertion: each `members[id][account]` slot
    ///      reads back as 1 (the bool means "blocked" for BLOCKLIST
    ///      policies; the slot value is still 1 in the canonical
    ///      Solidity bool encoding, even though `isAuthorized` returns
    ///      false for blocked accounts).
    function test_createPolicyWithAccounts_success_seedsBlocklist(
        address caller,
        address admin_,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        accounts = _boundAccounts(accounts);
        vm.prank(caller);
        uint64 policyId =
            policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.BLOCKLIST, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertFalse(policyRegistry.isAuthorized(policyId, accounts[i]));
            assertEq(
                uint256(
                    vm.load(address(policyRegistry), MockPolicyRegistryStorage.policyMemberSlot(policyId, accounts[i]))
                ),
                uint256(1),
                "members[id][account] slot must be set after blocklist seed (1 == blocked)"
            );
        }
    }

    /// @notice Verifies the seeding step on an allowlist policy emits AllowlistUpdated with the full batch
    /// @dev Batch event integrity for the initial seed; canonical event test lives in updateAllowlist.t.sol
    function test_createPolicyWithAccounts_success_emitsAllowlistUpdatedOnSeed(
        address caller,
        address admin_,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        accounts = _boundAccounts(accounts);
        uint64 expectedId = _predictNextPolicyId(IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.AllowlistUpdated(expectedId, caller, true, accounts);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, accounts);
    }

    /// @notice Verifies the seeding step on a blocklist policy emits BlocklistUpdated with the full batch
    /// @dev Batch event integrity for the initial seed; canonical event test lives in updateBlocklist.t.sol
    function test_createPolicyWithAccounts_success_emitsBlocklistUpdatedOnSeed(
        address caller,
        address admin_,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        accounts = _boundAccounts(accounts);
        uint64 expectedId = _predictNextPolicyId(IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.BlocklistUpdated(expectedId, caller, true, accounts);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.BLOCKLIST, accounts);
    }

    /// @notice Verifies createPolicyWithAccounts succeeds with an empty accounts array
    /// @dev Equivalent to createPolicy when accounts.length == 0; no batch event emitted
    function test_createPolicyWithAccounts_success_emptyAccounts(address caller, address admin_, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        address[] memory empty = new address[](0);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicyWithAccounts(admin_, pt, empty);
        assertTrue(policyRegistry.policyExists(policyId));
    }

    /// @notice Verifies createPolicyWithAccounts reverts when the batch exceeds MAX_BATCH_SIZE
    /// @dev Mirrors the Rust precompile's batch limit; checks
    ///      BatchSizeTooLarge(maxBatchSize). Fuzz drives `overflow` so the test exercises
    ///      arbitrary over-the-limit sizes, not just the immediate neighbor.
    function test_createPolicyWithAccounts_revert_batchSizeTooLarge(
        address caller,
        address admin_,
        uint8 typeIdx,
        uint8 overflow
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, pt, accounts);
    }

    /// @notice Verifies createPolicyWithAccounts accepts a batch exactly at MAX_BATCH_SIZE
    /// @dev Boundary check: the limit is inclusive (length == MAX_BATCH_SIZE succeeds).
    function test_createPolicyWithAccounts_success_batchAtLimit(address caller, address admin_, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        address[] memory accounts = _makeAccounts(MAX_BATCH_SIZE);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicyWithAccounts(admin_, pt, accounts);
        assertTrue(policyRegistry.policyExists(policyId));
    }

    /// @notice Verifies `ZeroAddress` wins when both zero admin and oversized batch fail
    /// @dev Pins the Rust precompile's check precedence (`validate_create_policy_inputs`
    ///      → `require_account_batch_size`). Mirrors Rust test
    ///      `create_policy_with_accounts_zero_admin_precedes_batch_size_revert` in
    ///      `crates/common/precompiles/src/policy/storage.rs`. Guards the entry-point check
    ///      order: if a later refactor reorders these two checks, this test fails.
    function test_createPolicyWithAccounts_revert_zeroAdmin_precedes_batchSizeTooLarge(
        address caller,
        uint8 typeIdx,
        uint8 overflow
    ) public {
        _assumeValidCaller(caller);
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(address(0), pt, accounts);
    }
}
