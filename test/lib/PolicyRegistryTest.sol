// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "test/lib/BaseTest.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";
import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

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
    /// @dev    Reads `nextCounter` directly via `vm.load` and applies the same
    ///         floor / encoding as `MockPolicyRegistry._create`.
    function _predictNextPolicyId(IPolicyRegistry.PolicyType policyType) internal view returns (uint64) {
        uint56 counter =
            uint56(uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())));
        if (counter < 2) counter = 2;
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
}
