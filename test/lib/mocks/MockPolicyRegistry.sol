// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

/// @notice Placeholder mock for the `IPolicyRegistry` precompile.
///
/// Implements only the built-in sentinel semantics that B20 tests rely
/// on to exercise policy gating without configuring custom policies:
///   - `isAuthorized(0, _)` → true  (ALWAYS_ALLOW, built-in ID 0)
///   - `isAuthorized(1, _)` → false (ALWAYS_BLOCK, built-in ID 1)
///   - `policyExists` returns true for those two built-ins
///   - `policyType` returns the matching PolicyType enum for those two
///
/// Built-in ID assignments updated per IPolicyRegistry's
/// ALWAYS_ALLOW = 0, ALWAYS_BLOCK = 1 design (PR #24): the built-in
/// IDs are now the small numeric values that match the PolicyType
/// ordinals rather than the previous (0, type(uint64).max) convention.
///
/// Every other method reverts pending the full mock implementation in
/// a follow-up PR. Custom policy creation, admin rotation, and
/// membership mutation are out of scope until then.
contract MockPolicyRegistry is IPolicyRegistry {
    uint64 internal constant ALWAYS_ALLOW_ID = 0;
    uint64 internal constant ALWAYS_BLOCK_ID = 1;

    function isAuthorized(uint64 policyId, address /*account*/ ) external pure returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_BLOCK_ID) return false;
        revert PolicyNotFound();
    }

    function policyExists(uint64 policyId) external pure returns (bool) {
        return policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID;
    }

    function createPolicy(address, PolicyType) external pure returns (uint64) {
        revert("MockPolicyRegistry: not implemented");
    }

    function createPolicyWithAccounts(address, PolicyType, address[] calldata) external pure returns (uint64) {
        revert("MockPolicyRegistry: not implemented");
    }

    function stageUpdateAdmin(uint64, address) external pure {
        revert("MockPolicyRegistry: not implemented");
    }

    function finalizeUpdateAdmin(uint64) external pure {
        revert("MockPolicyRegistry: not implemented");
    }

    function renounceAdmin(uint64) external pure {
        revert("MockPolicyRegistry: not implemented");
    }

    function updateAllowlist(uint64, bool, address[] calldata) external pure {
        revert("MockPolicyRegistry: not implemented");
    }

    function updateBlocklist(uint64, bool, address[] calldata) external pure {
        revert("MockPolicyRegistry: not implemented");
    }

    function nextPolicyId(PolicyType) external pure returns (uint64) {
        revert("MockPolicyRegistry: not implemented");
    }

    function policyType(uint64 policyId) external pure returns (PolicyType) {
        if (policyId == ALWAYS_ALLOW_ID) return PolicyType.ALWAYS_ALLOW;
        if (policyId == ALWAYS_BLOCK_ID) return PolicyType.ALWAYS_BLOCK;
        revert("MockPolicyRegistry: not implemented");
    }

    function policyAdmin(uint64) external pure returns (address) {
        revert("MockPolicyRegistry: not implemented");
    }

    function pendingPolicyAdmin(uint64) external pure returns (address) {
        revert("MockPolicyRegistry: not implemented");
    }
}
