// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `batchMint` (asset variant).
///
/// @notice **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(MINT)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(MINT_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. LENGTH_MISMATCH (`recipients.length != amounts.length`) → `LengthMismatch`
///         4. EMPTY_BATCH (`recipients.length == 0`) → `EmptyBatch`
///         5. ZERO-RECEIVER (per-element inline guard) → `InvalidReceiver`
///         6..N. Per-element `_mint` body (see `mint_revertOrder.t.sol`):
///               POLICY → CAP
///
///         The pairs within `_mint`'s body are already pinned by
///         `mint_revertOrder.t.sol`. This file pins the batch-level
///         preconditions (PAUSE, ROLE, LENGTH_MISMATCH, EMPTY_BATCH)
///         against each other and against the first per-element check
///         they encounter.
contract B20AssetBatchMintRevertOrderTest is B20AssetTest {
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

    // --- Pairs where PAUSE wins (PAUSE is canonical first) ---

    /// @notice PAUSE beats ROLE.
    function test_batchMint_revertOrder_pause_beats_role(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != minter);
        _pause(IB20.PausableFeature.MINT);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        asset().batchMint(_twoAddrs, _twoUints);
    }

    /// @notice PAUSE beats LENGTH_MISMATCH.
    function test_batchMint_revertOrder_pause_beats_lengthMismatch() public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        asset().batchMint(_twoAddrs, _twoUints);
    }

    /// @notice PAUSE beats EMPTY_BATCH.
    function test_batchMint_revertOrder_pause_beats_emptyBatch() public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        asset().batchMint(_emptyAddrs, _emptyUints);
    }

    // --- Pairs where ROLE wins (PAUSE not violated) ---

    /// @notice ROLE beats LENGTH_MISMATCH.
    /// @dev Role modifier fires before the body's length check.
    function test_batchMint_revertOrder_role_beats_lengthMismatch(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != minter);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        asset().batchMint(_twoAddrs, _twoUints);
    }

    /// @notice ROLE beats EMPTY_BATCH.
    function test_batchMint_revertOrder_role_beats_emptyBatch(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != minter);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        asset().batchMint(_emptyAddrs, _emptyUints);
    }

    // --- Pairs where LENGTH_MISMATCH / EMPTY_BATCH win (PAUSE + ROLE satisfied) ---

    /// @notice LENGTH_MISMATCH beats per-element `_mint` body checks.
    /// @dev With role granted and pause not set, the length check in batchMint's
    ///      body fires before the per-element loop runs.
    function test_batchMint_revertOrder_lengthMismatch_beats_mintBody() public {
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.LengthMismatch.selector, uint256(2), uint256(1)));
        asset().batchMint(_twoAddrs, _twoUints);
    }

    /// @notice EMPTY_BATCH beats per-element `_mint` body checks.
    function test_batchMint_revertOrder_emptyBatch_beats_mintBody() public {
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.prank(minter);
        vm.expectRevert(IB20Asset.EmptyBatch.selector);
        asset().batchMint(_emptyAddrs, _emptyUints);
    }
}
