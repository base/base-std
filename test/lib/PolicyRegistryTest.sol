// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `IPolicyRegistry` unit tests.
///
/// `setUp` is mock-vs-live aware: the etch is skipped when the canonical
/// precompile address already has code (live mode under `--fork-url`).
/// In mock mode the mock contract is etched at the canonical address so
/// the same test body executes against either backend without branching.
///
/// The mock contract is added in a follow-up PR; until then, calls to
/// the registry revert at runtime under mock mode. The unit stubs in this
/// spec PR are not yet implemented, so this is intentional.
contract PolicyRegistryTest is Test {
    // -- Actors --
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    // -- Precompile handle --
    IPolicyRegistry internal policyRegistry = StdPrecompiles.POLICY_REGISTRY;

    // -- Setup --
    function setUp() public virtual {
        vm.label(StdPrecompiles.POLICY_REGISTRY_ADDRESS, "PolicyRegistry");
        vm.label(admin, "admin");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(attacker, "attacker");

        // TODO(mock PR): if (StdPrecompiles.POLICY_REGISTRY_ADDRESS.code.length == 0) {
        //     vm.etch(StdPrecompiles.POLICY_REGISTRY_ADDRESS, type(MockPolicyRegistry).runtimeCode);
        // }
    }

    // -- Action wrappers --

    /// @notice Create an empty allowlist policy with explicit admin and caller.
    function _createAllowlist(address caller, address admin_) internal returns (uint64 policyId) {
        vm.prank(caller);
        return policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
    }

    /// @notice Create an empty allowlist policy with defaults (alice creator, `admin` as admin).
    function _createAllowlist() internal returns (uint64 policyId) {
        return _createAllowlist(alice, admin);
    }

    /// @notice Create an empty blocklist policy with explicit admin and caller.
    function _createBlocklist(address caller, address admin_) internal returns (uint64 policyId) {
        vm.prank(caller);
        return policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.BLOCKLIST);
    }

    /// @notice Create an empty blocklist policy with defaults.
    function _createBlocklist() internal returns (uint64 policyId) {
        return _createBlocklist(alice, admin);
    }

    /// @notice Create an allowlist policy seeded with `accounts`.
    function _createAllowlistWith(address caller, address admin_, address[] memory accounts)
        internal
        returns (uint64 policyId)
    {
        vm.prank(caller);
        return policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, accounts);
    }

    /// @notice Create a blocklist policy seeded with `accounts`.
    function _createBlocklistWith(address caller, address admin_, address[] memory accounts)
        internal
        returns (uint64 policyId)
    {
        vm.prank(caller);
        return policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.BLOCKLIST, accounts);
    }

    /// @notice Stage an admin transfer; pranks as the current admin.
    function _stageAdmin(uint64 policyId, address currentAdmin, address newAdmin) internal {
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
    }

    /// @notice Finalize an admin transfer; pranks as the pending admin.
    function _finalizeAdmin(uint64 policyId, address pendingAdmin) internal {
        vm.prank(pendingAdmin);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    /// @notice Renounce administration; pranks as the current admin.
    function _renounceAdmin(uint64 policyId, address currentAdmin) internal {
        vm.prank(currentAdmin);
        policyRegistry.renounceAdmin(policyId);
    }
}
