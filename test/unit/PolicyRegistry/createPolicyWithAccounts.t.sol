// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryCreatePolicyWithAccountsTest is PolicyRegistryTest {
    /// @notice Verifies createPolicyWithAccounts reverts when admin is the zero address
    /// @dev Required-field guard; checks ZeroAddress() error
    function test_createPolicyWithAccounts_revert_zeroAdmin(address caller, address[] memory accounts) public {
        _assumeValidCaller(caller);
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(address(0), IPolicyRegistry.PolicyType.ALLOWLIST, accounts);
    }

    /// @notice Verifies createPolicyWithAccounts reverts for any policyType outside the enum
    /// @dev Fuzz confirms only ALLOWLIST / BLOCKLIST are accepted; checks InvalidPolicyType() error
    function test_createPolicyWithAccounts_revert_invalidPolicyType(
        address caller,
        address admin_,
        uint8 policyTypeInt,
        address[] memory accounts
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.assume(policyTypeInt != 2 && policyTypeInt != 3);
        vm.assume(policyTypeInt < 4);
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        IPolicyRegistry.PolicyType invalidType = IPolicyRegistry.PolicyType(policyTypeInt);
        vm.expectRevert(IPolicyRegistry.InvalidPolicyType.selector);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, invalidType, accounts);
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
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        vm.prank(caller);
        uint64 policyId =
            policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertTrue(policyRegistry.isAuthorized(policyId, accounts[i]));
            assertEq(
                uint256(
                    vm.load(
                        address(policyRegistry),
                        MockPolicyRegistryStorage.policyMemberSlot(policyId, accounts[i])
                    )
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
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        vm.prank(caller);
        uint64 policyId =
            policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.BLOCKLIST, accounts);
        for (uint256 i = 0; i < accounts.length; ++i) {
            assertFalse(policyRegistry.isAuthorized(policyId, accounts[i]));
            assertEq(
                uint256(
                    vm.load(
                        address(policyRegistry),
                        MockPolicyRegistryStorage.policyMemberSlot(policyId, accounts[i])
                    )
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
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 expectedId = policyRegistry.nextPolicyId(IPolicyRegistry.PolicyType.ALLOWLIST);
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
        uint256 len = bound(accounts.length, 0, 5);
        assembly { mstore(accounts, len) }
        uint64 expectedId = policyRegistry.nextPolicyId(IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.BlocklistUpdated(expectedId, caller, true, accounts);
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.BLOCKLIST, accounts);
    }

    /// @notice Verifies createPolicyWithAccounts succeeds with an empty accounts array
    /// @dev Equivalent to createPolicy when accounts.length == 0; no batch event emitted
    function test_createPolicyWithAccounts_success_emptyAccounts(address caller, address admin_, uint8 policyTypeInt)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.assume(policyTypeInt == 2 || policyTypeInt == 3);
        IPolicyRegistry.PolicyType pt = IPolicyRegistry.PolicyType(policyTypeInt);
        address[] memory empty = new address[](0);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicyWithAccounts(admin_, pt, empty);
        assertTrue(policyRegistry.policyExists(policyId));
    }
}
