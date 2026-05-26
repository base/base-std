// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PolicyRegistry} from "src/impls/PolicyRegistry.sol";
import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";
import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

import {BaseTest} from "test/lib/BaseTest.sol";

/// @notice Base test contract for `PolicyRegistry` unit tests.
///
/// Deploys a production `PolicyRegistry` proxy (with `admin` as owner)
/// in addition to the precompile-mock etch wiring inherited from `BaseTest`.
/// The etched mock at `StdPrecompiles.POLICY_REGISTRY_ADDRESS` is still
/// used by B-20 and activation-registry tests that call across precompiles;
/// this base's `policyRegistry` handle points to the production deployment.
contract PolicyRegistryTest is BaseTest {
    // ============================================================
    //                       CONSTANTS
    // ============================================================

    /// @dev Mirrors `PolicyRegistry.ALWAYS_ALLOW_ID` for compile-time access in tests.
    uint64 internal constant ALWAYS_ALLOW_ID = 0;

    /// @dev Mirrors `PolicyRegistry.ALWAYS_BLOCK_ID` for compile-time access in tests.
    uint64 internal constant ALWAYS_BLOCK_ID = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | 1;

    /// @dev Counter value after built-in sentinel initialization. Custom policies start here.
    uint56 internal constant BUILTIN_POLICY_COUNT = 2;

    // ============================================================
    //                       REGISTRY HANDLE
    // ============================================================

    IPolicyRegistry internal policyRegistry;

    // ============================================================
    //                          SETUP
    // ============================================================

    function setUp() public virtual override {
        super.setUp();

        PolicyRegistry impl = new PolicyRegistry();
        policyRegistry = IPolicyRegistry(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(PolicyRegistry.initialize, (admin))))
        );
        vm.label(address(policyRegistry), "PolicyRegistry");
    }

    // ============================================================
    //                          HELPERS
    // ============================================================

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

    /// @notice Maps a fuzz seed to ALLOWLIST or BLOCKLIST.
    function _creatablePolicyType(uint8 idx) internal pure returns (IPolicyRegistry.PolicyType) {
        return idx % 2 == 0 ? IPolicyRegistry.PolicyType.ALLOWLIST : IPolicyRegistry.PolicyType.BLOCKLIST;
    }

    /// @notice Predict the ID the next `createPolicy(_, policyType)` would assign.
    /// @dev    Reads `nextCounter` directly via `vm.load`.
    function _predictNextPolicyId(IPolicyRegistry.PolicyType policyType) internal view returns (uint64) {
        uint56 counter =
            uint56(uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())));
        if (counter < BUILTIN_POLICY_COUNT) counter = BUILTIN_POLICY_COUNT;
        return (uint64(uint8(policyType)) << 56) | uint64(counter);
    }

    // ============================================================
    //                       ARRAY-BOUND HELPER
    // ============================================================

    /// @notice Bounds a fuzzed `address[]` to length 0..5 by
    ///         overwriting its in-memory length word.
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
    uint256 internal constant MAX_BATCH_SIZE = 64;

    /// @notice Build an `address[]` of length `n` with deterministic, distinct, non-zero entries.
    function _makeAccounts(uint256 n) internal pure returns (address[] memory accounts) {
        accounts = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            accounts[i] = address(uint160(0x1000 + i));
        }
    }
}
