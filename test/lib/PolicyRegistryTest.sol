// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "test/lib/BaseTest.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `IPolicyRegistry` unit tests.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the registry handle and policy-creation helpers.
contract PolicyRegistryTest is BaseTest {
    // -- Precompile handle --
    IPolicyRegistry internal policyRegistry = StdPrecompiles.POLICY_REGISTRY;

    // -- Helpers --

    /// @notice Create an ALLOWLIST policy with explicit admin and caller.
    function _createAllowlist(address caller, address policyAdmin) internal returns (uint64 policyId) {
        vm.prank(caller);
        policyId = policyRegistry.createPolicy(policyAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
    }

    /// @notice Create an ALLOWLIST policy as the default admin (no prank needed at call site).
    function _createAllowlist() internal returns (uint64 policyId) {
        policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
    }

    /// @notice Create a BLOCKLIST policy with explicit admin and caller.
    function _createBlocklist(address caller, address policyAdmin) internal returns (uint64 policyId) {
        vm.prank(caller);
        policyId = policyRegistry.createPolicy(policyAdmin, IPolicyRegistry.PolicyType.BLOCKLIST);
    }

    /// @notice Create a BLOCKLIST policy as the default admin.
    function _createBlocklist() internal returns (uint64 policyId) {
        policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
    }

    // ============================================================
    //                    POLICY-TYPE FUZZ HELPERS
    // ============================================================
    // The `PolicyType` enum has four values; only the last two
    // (ALLOWLIST = 2, BLOCKLIST = 3) are valid arguments to
    // `createPolicy` / `createPolicyWithAccounts`. Tests that fuzz the
    // enum byte partition into three regions: creatable, non-creatable
    // but well-formed (the two reserved sentinels), and out-of-range.
    // The helpers below name those regions so call sites read
    // semantically instead of carrying the literal byte values.

    /// @notice Maps a fuzz seed to one of the two creatable policy
    ///         types (ALLOWLIST or BLOCKLIST). Use in success tests and
    ///         in revert tests where the policy creates successfully
    ///         but reverts on a separate guard (e.g. zero admin).
    function _creatablePolicyType(uint8 idx) internal pure returns (IPolicyRegistry.PolicyType) {
        return idx % 2 == 0 ? IPolicyRegistry.PolicyType.ALLOWLIST : IPolicyRegistry.PolicyType.BLOCKLIST;
    }

    /// @notice Maps a fuzz seed to one of the two reserved
    ///         non-creatable enum values (ALWAYS_ALLOW or
    ///         ALWAYS_BLOCK). Use in tests asserting `InvalidPolicyType`
    ///         on `createPolicy` / `createPolicyWithAccounts`: those
    ///         enum values cast successfully but the registry rejects
    ///         them at the type guard.
    function _nonCreatablePolicyType(uint8 idx) internal pure returns (IPolicyRegistry.PolicyType) {
        return idx % 2 == 0 ? IPolicyRegistry.PolicyType.ALWAYS_ALLOW : IPolicyRegistry.PolicyType.ALWAYS_BLOCK;
    }

    // ============================================================
    //                       ARRAY-BOUND HELPER
    // ============================================================

    /// @notice Bounds a fuzzed `address[]` to length 0..5 by
    ///         overwriting its in-memory length word. Returns the same
    ///         memory pointer so the helper can be used inline.
    /// @dev    Foundry-fuzzed `bytes` / arrays default to lengths up to
    ///         `fuzz.max-test-rejects`-bounded sizes. For per-element
    ///         membership tests we want a small, predictable spread; 5
    ///         is large enough to exercise multi-element batches without
    ///         blowing up gas. The assembly is centralized here so call
    ///         sites stay focused on what they're testing.
    function _boundAccounts(address[] memory accounts) internal pure returns (address[] memory) {
        uint256 len = bound(accounts.length, 0, 5);
        // forge-lint: disable-next-line(asm-keccak256)
        assembly {
            mstore(accounts, len)
        }
        return accounts;
    }
}
