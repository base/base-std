// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @title Differential check-order tests for `stageUpdateAdmin`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. POLICY-NOT-FOUND (`_requireCustom`: packed == 0) → `PolicyNotFound`
///         2. UNAUTHORIZED (`_decodeAdmin(packed) != msg.sender`) → `Unauthorized`
///
///         C(2, 2) = 1 pair.
contract PolicyRegistryStageUpdateAdminRevertOrderTest is PolicyRegistryTest {
    /// @notice POLICY-NOT-FOUND beats UNAUTHORIZED.
    /// @dev policyId does not exist (packed == 0) AND caller is not the policy admin.
    ///      `_requireCustom` reverts with `PolicyNotFound` before the admin check runs.
    function test_stageUpdateAdmin_revertOrder_policyNotFound_beats_unauthorized(
        address caller,
        uint64 seed,
        address newAdmin
    ) public {
        _assumeValidCaller(caller);
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);

        // Both conditions apply independently:
        // - PolicyNotFound: policyId has never been created (policies[policyId] == 0).
        // - Unauthorized: _decodeAdmin(0) == address(0) != caller (caller is non-zero).
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
    }
}
