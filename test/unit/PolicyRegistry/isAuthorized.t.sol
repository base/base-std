// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract PolicyRegistryIsAuthorizedTest is PolicyRegistryTest {
    /// @notice Verifies isAuthorized on an uncreated ALLOWLIST id returns false
    /// @dev Documents empty-member-set semantics: no existence check, so an
    ///      empty allowlist authorizes no one.
    function test_isAuthorized_success_uncreatedAllowlistReturnsFalse(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 policyId = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(counter);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized on an uncreated BLOCKLIST id returns true
    /// @dev Empty-member-set semantics: an empty blocklist blocks no one.
    function test_isAuthorized_success_uncreatedBlocklistReturnsTrue(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 policyId = (uint64(uint8(IPolicyRegistry.PolicyType.BLOCKLIST)) << 56) | uint64(counter);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns false for any id whose top byte
    ///         is outside the PolicyType enum range.
    /// @dev Malformed-ID short-circuit returns false rather than reverting.
    function test_isAuthorized_success_falseForMalformedId(uint64 seed, address account) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns true for any account under ALWAYS_ALLOW_ID
    /// @dev Built-in sentinel semantics: ALWAYS_ALLOW_ID returns true unconditionally
    function test_isAuthorized_success_alwaysAllowBuiltin(address account) public view {
        assertTrue(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_ALLOW_ID, account));
    }

    /// @notice Verifies isAuthorized returns false for any account under ALWAYS_BLOCK_ID
    /// @dev Built-in sentinel semantics: ALWAYS_BLOCK_ID returns false unconditionally
    function test_isAuthorized_success_alwaysBlockBuiltin(address account) public view {
        assertFalse(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_BLOCK_ID, account));
    }

    /// @notice Verifies isAuthorized returns true for an allowlist member
    /// @dev Allowlist semantics: membership grants authorization
    function test_isAuthorized_success_allowlistMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateAllowlist(policyId, true, accounts);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns false for a non-member of an allowlist
    /// @dev Allowlist semantics: absence denies authorization
    function test_isAuthorized_success_allowlistNonMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns false for a blocklist member
    /// @dev Blocklist semantics: membership denies authorization
    function test_isAuthorized_success_blocklistMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateBlocklist(policyId, true, accounts);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns true for a non-member of a blocklist
    /// @dev Blocklist semantics: absence grants authorization
    function test_isAuthorized_success_blocklistNonMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }
}
