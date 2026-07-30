// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

/// @title Reorder-in-one-bracket e2e.
///
/// @notice The single-pending model rejects overlapping schedules, so a corporate action is
///         re-ordered by cancelling and re-scheduling atomically inside one `announce()` bracket
///         Both inner calls run via self-`delegatecall` preserving `msg.sender`,
///         so the operator's `OPERATOR_ROLE` gate passes on each.
contract B20AssetReorderTest is B20AssetTest {
    function test_reorder_success_cancelThenScheduleInOneBracket() public {
        uint256 firstEffectiveAt = block.timestamp + 1 days;
        _setUIMultiplier(2e18, firstEffectiveAt);

        uint256 secondMultiplier = 3e18;
        uint256 secondEffectiveAt = block.timestamp + 2 days;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IB20Asset.cancelScheduledMultiplier, ());
        calls[1] = abi.encodeCall(IB20Asset.setUIMultiplier, (secondMultiplier, secondEffectiveAt));

        _grantOperator();
        _announce(operator, calls, "reorder-2026-Q3", "reorder split", "https://disclosures.example/");

        // The live pending is now the second schedule; the first was cancelled, not overlapped.
        assertEq(asset().newUIMultiplier(), secondMultiplier, "pending target must be the re-scheduled multiplier");
        assertEq(asset().effectiveAt(), secondEffectiveAt, "pending effectiveAt must be the re-scheduled time");
        assertEq(
            asset().uiMultiplier(),
            asset().WAD_PRECISION(),
            "current multiplier unchanged until the new schedule matures"
        );

        vm.warp(secondEffectiveAt);
        assertEq(asset().uiMultiplier(), secondMultiplier, "re-scheduled multiplier flips in on maturity");
    }
}
