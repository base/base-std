// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "base-std-test/lib/BaseTest.sol";

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

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
    // The `PolicyType` enum has two values (BLOCKLIST = 0, ALLOWLIST = 1),
    // both creatable. The helper picks one from a fuzz seed.

    /// @notice Maps a fuzz seed to ALLOWLIST or BLOCKLIST.
    function _creatablePolicyType(uint8 idx) internal pure returns (IPolicyRegistry.PolicyType) {
        return idx % 2 == 0 ? IPolicyRegistry.PolicyType.ALLOWLIST : IPolicyRegistry.PolicyType.BLOCKLIST;
    }

    /// @notice Predict the ID the next `createPolicy(_, policyType)` would assign.
    /// @dev    Reads `nextCounter` directly via `vm.load`. When the registry
    ///         has not yet been initialized (counter == 0), the next
    ///         `createPolicy` call advances the counter past the built-in
    ///         sentinels before consuming it; the prediction matches by
    ///         clamping pre-init reads up to `BUILTIN_POLICY_COUNT`.
    function _predictNextPolicyId(IPolicyRegistry.PolicyType policyType) internal view returns (uint64) {
        uint56 counter = uint56(uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())));
        if (counter < PolicyRegistryConstants.BUILTIN_POLICY_COUNT) {
            counter = PolicyRegistryConstants.BUILTIN_POLICY_COUNT;
        }
        return (uint64(uint8(policyType)) << 56) | uint64(counter);
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

    // ============================================================
    //                       BATCH-LIMIT HELPERS
    // ============================================================

    /// @notice Per-call membership-batch limit enforced by the registry.
    /// @dev    Mirrors `MockPolicyRegistry.MAX_BATCH_SIZE`. Kept as a
    ///         test-side literal (rather than reading from the mock) so
    ///         fork tests against the real precompile use the same
    ///         compile-time constant.
    uint256 internal constant MAX_BATCH_SIZE = 64;

    /// @notice Build an `address[]` of length `n` with deterministic,
    ///         distinct, non-zero entries. Used by batch-limit tests
    ///         that need arrays straddling `MAX_BATCH_SIZE`.
    function _makeAccounts(uint256 n) internal pure returns (address[] memory accounts) {
        accounts = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            accounts[i] = address(uint160(0x1000 + i));
        }
    }
}
