// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "test/lib/BaseTest.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `IPolicyRegistry` unit tests.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the registry handle and policy create / admin
/// rotation helpers.
contract PolicyRegistryTest is BaseTest {
    // -- Precompile handle --
    IPolicyRegistry internal policyRegistry = StdPrecompiles.POLICY_REGISTRY;

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
