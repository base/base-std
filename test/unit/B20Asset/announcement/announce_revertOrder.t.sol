// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

/// @title Differential check-order tests for `announce`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(OPERATOR_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. ID-ALREADY-USED (`$.usedAnnouncementIds[id]`) → `AnnouncementIdAlreadyUsed`
///         3. (per-internalCall) MALFORMED (`_checkSelector` rejects < 4 bytes or self-call)
///            → `InternalCallMalformed` / `AnnouncementInProgress`
///         4. (per-internalCall) FAILED-DELEGATECALL (`delegatecall` reverts) → `InternalCallFailed`
///
///         Some pairs are unreachable because the violations are sequenced through
///         the loop body (MALFORMED check runs before the delegatecall, so a single
///         element can't both be MALFORMED and produce FAILED-DELEGATECALL; you'd
///         need two elements).
///
///         Selected pairs cover: ROLE-first invariant, ID-USED-fires-before-loop,
///         and the per-element MALFORMED-before-FAILED ordering.
contract B20AssetAnnounceRevertOrderTest is B20AssetTest {
    /// @dev A short blob with no valid selector (< 4 bytes).
    bytes internal constant MALFORMED_BLOB = hex"112233";

    /// @dev A well-formed selector that targets a nonexistent function (delegatecall returns false).
    bytes internal constant FAILING_INNER_CALL = hex"deadbeef";

    // --- Pairs where ROLE wins ---

    function test_announce_revertOrder_role_beats_idAlreadyUsed(address caller, string calldata id) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);
        _announce(id); // consume the id once
        // caller lacks OPERATOR_ROLE AND id is already used.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE));
        asset().announce(new bytes[](0), id, "desc", "uri");
    }

    function test_announce_revertOrder_role_beats_malformedInnerCall(address caller, string calldata id) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);
        // caller lacks role AND would supply a malformed inner call.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE));
        asset().announce(_singletonBytes(MALFORMED_BLOB), id, "desc", "uri");
    }

    // --- Pair where ID-ALREADY-USED wins ---

    function test_announce_revertOrder_idAlreadyUsed_beats_malformedInnerCall(string calldata id) public {
        _grantOperator();
        _announce(id); // consume the id once
        // id is now used AND we'd supply a malformed inner call. ID-USED fires before the loop.

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.AnnouncementIdAlreadyUsed.selector, id));
        asset().announce(_singletonBytes(MALFORMED_BLOB), id, "desc", "uri");
    }

    // --- Per-element ordering ---

    function test_announce_revertOrder_malformedInnerCall_beats_failedInnerCall(string calldata id) public {
        _grantOperator();
        // Two-element array: index 0 is MALFORMED (will be caught by _checkSelector),
        // index 1 would have caused FAILED-DELEGATECALL. The loop processes [0] first, so
        // MALFORMED fires first.
        bytes[] memory calls = new bytes[](2);
        calls[0] = MALFORMED_BLOB;
        calls[1] = FAILING_INNER_CALL;

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.InternalCallMalformed.selector, MALFORMED_BLOB));
        asset().announce(calls, id, "desc", "uri");
    }
}
