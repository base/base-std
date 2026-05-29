// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

/// @title Differential check-order tests for `batchBurn` (security variant).
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRoleStrict(BURN_FROM_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. LENGTH_MISMATCH (`accounts.length != amounts.length`) → `LengthMismatch`
///         3. EMPTY_BATCH (`accounts.length == 0`) → `EmptyBatch`
///         4. PAUSE (`_isPaused(BURN)`) → `ContractPaused`
///         5. BALANCE (per-element `_burnRaw`) → `InsufficientBalance`
///
///         Some pairs are not reachable because the violations are mutually
///         exclusive (LENGTH_MISMATCH vs EMPTY_BATCH) or because one check
///         short-circuits the loop where the other would fire
///         (LENGTH_MISMATCH/EMPTY_BATCH vs BALANCE — the loop never runs).
///         Reachable pairs: 7.
contract B20SecurityBatchBurnRevertOrderTest is B20SecurityTest {
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

    // --- Pairs where ROLE wins (via modifier, before any body check) ---
    //
    // Note: BURN_FROM_ROLE() is resolved before vm.prank because the view call
    // would otherwise consume the prank intended for batchBurn (same pattern as
    // _setRedeemPolicy in B20SecurityTest).

    function test_batchBurn_revertOrder_role_beats_lengthMismatch(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != burnFromActor);
        bytes32 role = security().BURN_FROM_ROLE();
        // _twoAddrs has length 2, _twoUints has length 1 → length mismatch.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, role));
        security().batchBurn(_twoAddrs, _twoUints);
    }

    function test_batchBurn_revertOrder_role_beats_emptyBatch(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != burnFromActor);
        bytes32 role = security().BURN_FROM_ROLE();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, role));
        security().batchBurn(_emptyAddrs, _emptyUints);
    }

    function test_batchBurn_revertOrder_role_beats_pause(address caller, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != burnFromActor);
        _pause(IB20.PausableFeature.BURN);
        bytes32 role = security().BURN_FROM_ROLE();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, role));
        security().batchBurn(_singletonAddresses(alice), _singletonUints(amount));
    }

    function test_batchBurn_revertOrder_role_beats_balance(address caller, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != burnFromActor);
        amount = bound(amount, 1, type(uint128).max);
        bytes32 role = security().BURN_FROM_ROLE();
        // alice has zero balance.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, role));
        security().batchBurn(_singletonAddresses(alice), _singletonUints(amount));
    }

    // --- Pairs where LENGTH_MISMATCH wins ---

    function test_batchBurn_revertOrder_lengthMismatch_beats_pause() public {
        _grantBurnFrom();
        _pause(IB20.PausableFeature.BURN);

        vm.prank(burnFromActor);
        vm.expectRevert(abi.encodeWithSelector(IB20Security.LengthMismatch.selector, uint256(2), uint256(1)));
        security().batchBurn(_twoAddrs, _twoUints);
    }

    // --- Pairs where EMPTY_BATCH wins ---

    function test_batchBurn_revertOrder_emptyBatch_beats_pause() public {
        _grantBurnFrom();
        _pause(IB20.PausableFeature.BURN);

        vm.prank(burnFromActor);
        vm.expectRevert(IB20Security.EmptyBatch.selector);
        security().batchBurn(_emptyAddrs, _emptyUints);
    }

    // --- Pair where PAUSE wins ---

    function test_batchBurn_revertOrder_pause_beats_balance(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _grantBurnFrom();
        _pause(IB20.PausableFeature.BURN);
        // alice has zero balance → BALANCE would fire if PAUSE didn't.

        vm.prank(burnFromActor);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        security().batchBurn(_singletonAddresses(alice), _singletonUints(amount));
    }
}
