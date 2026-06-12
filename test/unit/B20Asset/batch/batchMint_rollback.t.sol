// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";

/// @title B20AssetBatchMintRollbackTest
/// @notice Verifies a revert mid-batchMint leaves no orphan token state.
///
/// @dev    Sibling of `B20AssetBatchMintTest` (happy path) and
///         `B20AssetBatchMintRevertOrderTest` (check-order). This file
///         covers the precompile-storage checkpoint integration: when an
///         element past index 0 reverts, the per-element writes from the
///         earlier successful iterations must be rolled back.
///
///         Mock mode gets this for free from revm's journaled storage —
///         a passing test there just confirms revm works. The
///         signal is in live precompile mode against the real Rust precompile,
///         where any break in the `precompile-storage` journal hookup
///         would leave the earlier writes persisted across the revert.
///         Companion to the Rust-side unit tests.
contract B20AssetBatchMintRollbackTest is B20AssetTest {
    /// @notice batchMint that reverts on element 1 via supply-cap leaves balances + supply unchanged
    /// @dev    Element 0 mints under the cap (writes alice's balance and
    ///         totalSupply); element 1 would push totalSupply past the
    ///         cap and reverts. The journal must roll element 0's
    ///         writes back. Fuzzes both amounts so the test exercises a
    ///         range of "how much element 0 wrote before element 1
    ///         failed".
    function test_batchMint_rollback_revertMidBatch_supplyCapExceeded(uint64 a1Seed, uint64 a2Seed) public {
        // Fixed cap keeps the bounds simple; the property under test
        // doesn't depend on the cap value, only that element 0 fits and
        // (element 0 + element 1) does not.
        uint256 cap = 1_000_000;
        uint256 a1 = bound(uint256(a1Seed), 1, cap - 1);
        uint256 a2 = bound(uint256(a2Seed), cap - a1 + 1, cap * 2);

        vm.prank(admin);
        token.updateSupplyCap(cap);
        _grantRole(B20Constants.MINT_ROLE, minter);

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a1;
        amounts[1] = a2;

        // Snapshot the state the revert must leave untouched.
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.SupplyCapExceeded.selector, cap, a1 + a2));
        asset().batchMint(recipients, amounts);

        // Element 0's mint must have been rolled back by the journal.
        assertEq(token.balanceOf(alice), aliceBefore, "alice balance must be unchanged after rollback");
        assertEq(token.balanceOf(bob), bobBefore, "bob balance must be unchanged after rollback");
        assertEq(token.totalSupply(), supplyBefore, "totalSupply must be unchanged after rollback");
    }
}
