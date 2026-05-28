// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";
import {B20Constants} from "test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `batchMint` (security variant).
///
/// @notice **Canonical order (Solidity reference):**
///         1. LENGTH_MISMATCH (`recipients.length != amounts.length`) → `LengthMismatch`
///         2. EMPTY_BATCH (`recipients.length == 0`) → `EmptyBatch`
///         3..N. Per-element `_mint` checks (see `mint_revertOrder.t.sol`):
///               ROLE → ZERO-RECEIVER → PAUSE → POLICY → CAP
///
///         The pairs within `_mint`'s body are already pinned by
///         `mint_revertOrder.t.sol`. This file only pins the two batchMint-specific
///         preconditions (LENGTH_MISMATCH, EMPTY_BATCH) against the first per-element
///         check they encounter (ROLE), which transitively guarantees they fire
///         before every `_mint` body check.
contract B20SecurityBatchMintRevertOrderTest is B20SecurityTest {
    address[] internal _emptyAddrs;
    uint256[] internal _emptyUints;
    address[] internal _twoAddrs;
    uint256[] internal _twoUints;

    function setUp() public override {
        super.setUp();
        _twoAddrs.push(alice);
        _twoAddrs.push(bob);
        _twoUints.push(1);
    }

    /// @notice LENGTH_MISMATCH beats ROLE (and transitively everything inside `_mint`).
    /// @dev Caller lacks MINT_ROLE; arrays have mismatched lengths. LENGTH check
    ///      fires in `batchMint` body before `_mint` is invoked, so the role
    ///      modifier on `_mint` never runs.
    function test_batchMint_revertOrder_lengthMismatch_beats_mintBody(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != minter);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Security.LengthMismatch.selector, uint256(2), uint256(1)));
        security().batchMint(_twoAddrs, _twoUints);
    }

    /// @notice EMPTY_BATCH beats ROLE (and transitively everything inside `_mint`).
    function test_batchMint_revertOrder_emptyBatch_beats_mintBody(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != minter);

        vm.prank(caller);
        vm.expectRevert(IB20Security.EmptyBatch.selector);
        security().batchMint(_emptyAddrs, _emptyUints);
    }
}
