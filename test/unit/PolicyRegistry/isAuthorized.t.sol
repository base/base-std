// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryIsAuthorizedTest is PolicyRegistryTest {
    /// @notice Verifies isAuthorized reverts PolicyNotFound for a well-formed but uncreated id
    /// @dev Lookup guard for non-existent ids; uses a well-formed id so the malformed
    ///      check passes and the storage-lookup miss fires.
    function test_isAuthorized_revert_policyNotFound(uint64 seed, address account) public {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.isAuthorized(policyId, account);
    }

    /// @notice Verifies isAuthorized reverts MalformedPolicyId for any id whose top byte
    ///         is outside the PolicyType enum range.
    /// @dev Encoding invariant on the registry surface.
    function test_isAuthorized_revert_malformedPolicyId(uint64 seed, address account) public {
        uint64 policyId = _malformedPolicyId(seed);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.MalformedPolicyId.selector, policyId));
        policyRegistry.isAuthorized(policyId, account);
    }

    /// @notice Verifies isAuthorized returns true for any account under built-in id 0 (always-allow)
    /// @dev Built-in sentinel semantics: id 0 returns true unconditionally
    function test_isAuthorized_success_alwaysAllowBuiltin(address account) public view {
        assertTrue(policyRegistry.isAuthorized(0, account));
    }

    /// @notice Verifies isAuthorized returns false for any account under built-in id 1 (always-block)
    /// @dev Built-in sentinel semantics: id 1 returns false unconditionally
    function test_isAuthorized_success_alwaysBlockBuiltin(address account) public view {
        assertFalse(policyRegistry.isAuthorized(1, account));
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
