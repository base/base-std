// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPolicyTypeTest is PolicyRegistryTest {
    /// @notice Verifies policyType reverts for an unknown policy id
    /// @dev Lookup guard for non-existent ids; checks PolicyNotFound() error
    function test_policyType_revert_policyNotFound(uint64 policyId) public {
        // unimplemented
    }

    /// @notice Verifies policyType returns ALLOWLIST for an allowlist policy
    /// @dev Type readback matches the value passed to createPolicy
    function test_policyType_success_returnsAllowlist() public {
        // unimplemented
    }

    /// @notice Verifies policyType returns BLOCKLIST for a blocklist policy
    /// @dev Type readback matches the value passed to createPolicy
    function test_policyType_success_returnsBlocklist() public {
        // unimplemented
    }
}
