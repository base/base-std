// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";

/// @title B20SecurityBatchBurnRollbackTest
/// @notice Verifies a revert mid-batchBurn leaves no orphan token state.
///
/// @dev    Sibling of `B20SecurityBatchBurnTest` (happy path) and
///         `B20SecurityBatchBurnRevertOrderTest` (check-order). This file
///         covers the precompile-storage checkpoint integration: when an
///         element past index 0 reverts, the per-element debits from the
///         earlier successful iterations must be rolled back.
///
///         Mock mode gets this for free from revm's journaled storage.
///         The signal is in fork mode against the real Rust precompile,
///         where any break in the `precompile-storage` journal hookup
///         would leave the earlier debits persisted across the revert.
///         Companion to BOP-176 (Rust-side unit tests).
contract B20SecurityBatchBurnRollbackTest is B20SecurityTest {
    /// @notice batchBurn that reverts on element 1 via InsufficientBalance leaves balances + supply unchanged
    /// @dev    Element 0 burns exactly alice's balance to 0; element 1
    ///         then attempts to burn more than bob holds and reverts.
    ///         The journal must roll element 0's debit back, restoring
    ///         alice to her pre-call balance and totalSupply to its
    ///         pre-call value. Fuzzes alice's burn amount and bob's
    ///         shortfall so the test exercises a range of pre-revert
    ///         write sizes.
    function test_batchBurn_rollback_revertMidBatch_insufficientBalance(uint64 a1Seed, uint64 bobBalSeed) public {
        uint256 a1 = bound(uint256(a1Seed), 1, type(uint64).max);
        // bob is mid-batch and underfunded relative to amounts[1].
        uint256 bobBurnAmount = bound(uint256(bobBalSeed), 1, type(uint64).max);
        uint256 bobBal = bound(uint256(bobBalSeed), 0, bobBurnAmount - 1);

        _grantBurnFrom();
        _mint(alice, a1); // alice has exactly the burn amount → element 0 zeroes her
        _mint(bob, bobBal); // bob is short by at least 1 → element 1 reverts

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a1;
        amounts[1] = bobBurnAmount;

        // Snapshot the state the revert must leave untouched.
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(burnFromActor);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, bob, bobBal, bobBurnAmount));
        security().batchBurn(accounts, amounts);

        // Element 0's debit must have been rolled back by the journal.
        assertEq(token.balanceOf(alice), aliceBefore, "alice balance must be unchanged after rollback");
        assertEq(token.balanceOf(bob), bobBefore, "bob balance must be unchanged after rollback");
        assertEq(token.totalSupply(), supplyBefore, "totalSupply must be unchanged after rollback");
    }
}
