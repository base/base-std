// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryIsAuthorizedTest is PolicyRegistryTest {
    /// @notice Verifies isAuthorized reverts for an unknown policy id
    /// @dev Lookup guard for non-existent ids; checks PolicyNotFound() error
    function test_isAuthorized_revert_policyNotFound(uint64 policyId, address account) public {
        // unimplemented
    }

    /// @notice Verifies isAuthorized returns true for any account under built-in id 0 (always-allow)
    /// @dev Built-in sentinel semantics: id 0 returns true unconditionally
    function test_isAuthorized_success_alwaysAllowBuiltin(address account) public {
        // unimplemented
    }

    /// @notice Verifies isAuthorized returns false for any account under built-in id type(uint64).max
    /// @dev Built-in sentinel semantics: id uint64.max returns false unconditionally
    function test_isAuthorized_success_alwaysRejectBuiltin(address account) public {
        // unimplemented
    }

    /// @notice Verifies isAuthorized returns true for an allowlist member
    /// @dev Allowlist semantics: membership grants authorization
    function test_isAuthorized_success_allowlistMember(address account) public {
        // unimplemented
    }

    /// @notice Verifies isAuthorized returns false for a non-member of an allowlist
    /// @dev Allowlist semantics: absence denies authorization
    function test_isAuthorized_success_allowlistNonMember(address account) public {
        // unimplemented
    }

    /// @notice Verifies isAuthorized returns false for a blocklist member
    /// @dev Blocklist semantics: membership denies authorization
    function test_isAuthorized_success_blocklistMember(address account) public {
        // unimplemented
    }

    /// @notice Verifies isAuthorized returns true for a non-member of a blocklist
    /// @dev Blocklist semantics: absence grants authorization
    function test_isAuthorized_success_blocklistNonMember(address account) public {
        // unimplemented
    }
}
