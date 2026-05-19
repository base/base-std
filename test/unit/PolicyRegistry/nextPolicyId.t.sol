// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

contract PolicyRegistryNextPolicyIdTest is PolicyRegistryTest {
    /// @notice Verifies nextPolicyId(ALLOWLIST) returns the first ALLOWLIST-encoded id
    ///         the next createPolicy(_, ALLOWLIST) would assign
    /// @dev Per the policy ID encoding scheme (top byte = type discriminator,
    ///      ALLOWLIST counter skips local-id 0 to avoid colliding with the
    ///      always-allow built-in at encoded id 0), the first allowlist id is
    ///      `(uint64(uint8(PolicyType.ALLOWLIST)) << 56) | 1`
    function test_nextPolicyId_success_allowlistInitialEncoded() public {
        // unimplemented
    }

    /// @notice Verifies nextPolicyId(BLOCKLIST) returns the first BLOCKLIST-encoded id
    ///         the next createPolicy(_, BLOCKLIST) would assign
    /// @dev Per the policy ID encoding scheme, the first blocklist id is
    ///      `(uint64(uint8(PolicyType.BLOCKLIST)) << 56) | 0` — no skip on
    ///      non-ALLOWLIST counters (only ALLOWLIST collides with built-in 0)
    function test_nextPolicyId_success_blocklistInitialEncoded() public {
        // unimplemented
    }

    /// @notice Verifies nextPolicyId(type) advances by one (local-id) per
    ///         successful createPolicy(_, type) call
    /// @dev Per-type monotonic counter; check returned id equals the prior
    ///      nextPolicyId(type) value and that the top-byte discriminator stays
    ///      stable across the sequence
    function test_nextPolicyId_success_advancesPerCreate(IPolicyRegistry.PolicyType policyType, uint8 count) public {
        // unimplemented
    }

    /// @notice Verifies nextPolicyId(ALLOWLIST) and nextPolicyId(BLOCKLIST)
    ///         advance independently
    /// @dev Per-type counters do not share state; creating an allowlist must
    ///      not affect the next-blocklist-id value and vice versa
    function test_nextPolicyId_success_perTypeCountersIndependent(uint8 allowCount, uint8 blockCount) public {
        // unimplemented
    }
}
