// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @title PolicyRegistryCreatePolicyWithAccountsRollbackTest
/// @notice Verifies a revert from createPolicyWithAccounts leaves no orphan
///         registry state.
///
/// @dev    Sibling of `PolicyRegistryCreatePolicyWithAccountsTest` (happy
///         path + revert reasons). Distinct from the Rust-side unit
///         tests of `precompile-storage`: this exercises the precompile
///         in a real EVM execution context to verify the JournaledState
///         integration rolls back any partial writes — or, in the case
///         of an impl that validates before creating, that no writes
///         occur at all.
///
///         Currently the two impls reach the same end state via
///         different paths:
///         - The Solidity mock advances `nextCounter` and writes the
///           policy slot before checking the batch size, then relies on
///           revm's journal to roll back on revert.
///         - The Rust precompile validates batch size first and never
///           writes.
///         End state is identical in both: counter unchanged, predicted
///         policy slot still zero, `policyExists(predicted)` false.
contract PolicyRegistryCreatePolicyWithAccountsRollbackTest is PolicyRegistryTest {
    /// @notice An oversized batch reverts and leaves nextCounter + the predicted policy slot byte-identical
    /// @dev    Reads the relevant slots with `vm.load` before and after
    ///         the reverting call — the test's signal is the byte-level
    ///         equality, which is the strictest possible "state
    ///         unchanged" assertion across both mock and live precompile modes.
    function test_createPolicyWithAccounts_rollback_batchSizeTooLarge(
        address caller,
        address admin_,
        uint8 typeIdx,
        uint8 overflow
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);

        // Snapshot the registry state the revert must leave untouched.
        uint64 predictedId = _predictNextPolicyId(pt);
        bytes32 counterBefore = vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot());
        bytes32 policySlotBefore = vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(predictedId));

        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, pt, accounts);

        // Slots must be byte-identical to pre-revert.
        bytes32 counterAfter = vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot());
        bytes32 policySlotAfter = vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(predictedId));
        assertEq(counterAfter, counterBefore, "nextCounter slot must be unchanged after rollback");
        assertEq(policySlotAfter, policySlotBefore, "predicted policy slot must be unchanged after rollback");
        // And the predicted ID must not be reachable as an existing policy.
        assertFalse(policyRegistry.policyExists(predictedId), "predicted policy must not exist after rollback");
    }
}
