// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @title Differential check-order tests for `createPolicyWithAccounts`.
///
/// @notice **Canonical order (Solidity reference entry-point, pre-`_create`):**
///         1. ZERO-ADMIN (`admin == address(0)`) → `ZeroAddress`
///         2. BATCH-SIZE (`accounts.length > MAX_BATCH_SIZE`) → `BatchSizeTooLarge`
///
///         C(2, 2) = 1 pair.
///
///         The natspec on `createPolicyWithAccounts` explicitly annotates this ordering:
///         "Reverts with `ZeroAddress` … Takes precedence over `BatchSizeTooLarge`."
///         This test pins that annotation against the Solidity reference implementation.
contract PolicyRegistryCreatePolicyWithAccountsRevertOrderTest is PolicyRegistryTest {
    /// @notice ZERO-ADMIN beats BATCH-SIZE.
    /// @dev admin is address(0) AND accounts.length exceeds MAX_BATCH_SIZE.
    ///      The zero-admin guard is checked before the batch-size guard.
    function test_createPolicyWithAccounts_revertOrder_zeroAddress_beats_batchSizeTooLarge(
        address caller,
        uint8 typeIdx,
        uint8 overflow
    ) public {
        _assumeValidCaller(caller);
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);

        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        policyRegistry.createPolicyWithAccounts(address(0), pt, accounts);
    }
}
