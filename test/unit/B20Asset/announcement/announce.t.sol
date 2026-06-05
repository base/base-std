// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";

contract B20AssetAnnounceTest is B20AssetTest {
    /// @notice Verifies announce reverts when caller lacks OPERATOR_ROLE
    /// @dev Access control: announce is `onlyRole(OPERATOR_ROLE)`. Non-role-holders
    ///      hit AccessControlUnauthorizedAccount before any other check.
    function test_announce_revert_unauthorized(address caller, string calldata id) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE));
        asset().announce(new bytes[](0), id, "desc", "uri");
    }

    /// @notice Verifies announce reverts when an id has already been consumed
    /// @dev Single-use ids: re-calling announce with the same id reverts
    ///      AnnouncementIdAlreadyUsed(id).
    function test_announce_revert_idAlreadyUsed(string calldata id) public {
        _announce(id);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.AnnouncementIdAlreadyUsed.selector, id));
        asset().announce(new bytes[](0), id, "desc", "uri");
    }

    /// @notice Verifies announce reverts when an internalCalls blob is shorter than 4 bytes
    /// @dev Malformed-payload guard: a too-short blob has no function selector to validate;
    ///      checks InternalCallMalformed(call).
    function test_announce_revert_internalCallMalformed(bytes calldata shortBlob) public {
        vm.assume(shortBlob.length < 4);
        _grantOperator();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.InternalCallMalformed.selector, shortBlob));
        asset().announce(_singletonBytes(shortBlob), "id-malformed", "desc", "uri");
    }

    /// @notice Verifies announce reverts when an internalCall re-invokes announce itself
    /// @dev Recursion guard: the bracket must stay exactly one level deep so indexers can
    ///      rely on Announcement / EndAnnouncement pairing. Inner self-`announce` reverts
    ///      AnnouncementInProgress.
    function test_announce_revert_recursion() public {
        _grantOperator();
        bytes[] memory inner = _singletonBytes(
            abi.encodeWithSelector(IB20Asset.announce.selector, new bytes[](0), "inner", "desc", "uri")
        );

        vm.prank(operator);
        vm.expectRevert(IB20Asset.AnnouncementInProgress.selector);
        asset().announce(inner, "outer", "desc", "uri");
    }

    /// @notice Verifies a failing inner call reverts the entire announcement
    /// @dev Atomicity: an inner-call revert unwinds the whole transaction so no
    ///      Announcement event is ever observable without its matching EndAnnouncement.
    ///      `InternalCallFailed(call)` carries the offending blob. We trigger it by
    ///      passing an updateName call which requires METADATA_ROLE that the operator lacks —
    ///      the inner revert wraps as InternalCallFailed at the outer layer.
    function test_announce_revert_innerCallFailed() public {
        _grantOperator();
        bytes memory failingCall = abi.encodeWithSelector(IB20.updateName.selector, "rebrand");

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.InternalCallFailed.selector, failingCall));
        asset().announce(_singletonBytes(failingCall), "fail-id", "desc", "uri");
    }

    /// @notice Verifies a failed announcement does NOT consume the id (atomicity)
    /// @dev The whole tx unwinds on inner-call failure, including the
    ///      `usedAnnouncementIds[id] = true` write that announce performs before the
    ///      inner-call loop. A subsequent announce with the same id must succeed.
    function test_announce_revert_atomicityRestoresIdState() public {
        _grantOperator();
        bytes memory failingCall = abi.encodeWithSelector(IB20.updateName.selector, "rebrand");

        vm.prank(operator);
        try asset().announce(_singletonBytes(failingCall), "atomic-id", "desc", "uri") {
            revert("expected revert");
        } catch { /* expected */ }

        assertFalse(asset().isAnnouncementIdUsed("atomic-id"), "failed announce must not consume the id");

        // The same id can now be reused successfully.
        _announce("atomic-id");
        assertTrue(asset().isAnnouncementIdUsed("atomic-id"), "second announce must consume the id");
    }

    /// @notice Verifies pure-announcement (empty internalCalls) succeeds and marks id used
    /// @dev Disclosure-only path: no inner calls, just the surrounding event pair.
    function test_announce_success_pureDisclosure(string calldata id) public {
        _announce(id);
        assertTrue(asset().isAnnouncementIdUsed(id), "pure announce must consume the id");
    }

    /// @notice Verifies announce executes a single inner call against the token via delegatecall
    /// @dev msg.sender preservation: the inner call sees the operator as `msg.sender`
    ///      (not the token). We verify by passing a grantRole inner call — the role admin
    ///      check resolves against the operator, who holds DEFAULT_ADMIN_ROLE (the operator
    ///      actor here also gets admin, see setup) so the grant lands successfully.
    function test_announce_success_executesInnerCall() public {
        _grantOperator();
        // Operator needs DEFAULT_ADMIN_ROLE for the inner grantRole to authorize.
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, operator);

        bytes memory inner = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.BURN_ROLE, bob);
        bytes[] memory calls = _singletonBytes(inner);

        _announce(operator, calls, "exec-id", "desc", "uri");
        assertTrue(token.hasRole(B20Constants.BURN_ROLE, bob), "inner grantRole must take effect");
    }

    /// @notice Verifies announce executes multiple inner calls in order
    /// @dev Order invariant: inner calls execute in index order; cumulative effect equals the
    ///      sum of each call applied sequentially.
    function test_announce_success_executesMultipleInnerCallsInOrder() public {
        _grantOperator();
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, operator);

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.BURN_ROLE, alice);
        calls[1] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.BURN_ROLE, bob);
        calls[2] = abi.encodeWithSelector(IB20.grantRole.selector, B20Constants.PAUSE_ROLE, alice);

        _announce(operator, calls, "multi-id", "desc", "uri");
        assertTrue(token.hasRole(B20Constants.BURN_ROLE, alice), "call 0 must take effect");
        assertTrue(token.hasRole(B20Constants.BURN_ROLE, bob), "call 1 must take effect");
        assertTrue(token.hasRole(B20Constants.PAUSE_ROLE, alice), "call 2 must take effect");
    }

    /// @notice Verifies announce emits Announcement(caller, id, description, uri)
    /// @dev Event integrity for the disclosure header. caller is indexed so consumers can
    ///      filter on operator address.
    function test_announce_success_emitsAnnouncement() public {
        _grantOperator();
        vm.expectEmit(true, false, false, true, address(token));
        emit IB20Asset.Announcement(operator, "announce-emit", "Q3 split", "https://x.example/split");
        _announce(operator, new bytes[](0), "announce-emit", "Q3 split", "https://x.example/split");
    }

    /// @notice Verifies announce emits EndAnnouncement(id) with the matching id
    /// @dev Event integrity for the closing marker. The id field hardens cross-tx indexing
    ///      so consumers can join open/close even when scanning logs in isolation.
    function test_announce_success_emitsEndAnnouncement(string calldata id) public {
        _grantOperator();
        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Asset.EndAnnouncement(id);
        _announce(operator, new bytes[](0), id, "desc", "uri");
    }

    /// @notice Verifies Announcement strictly precedes EndAnnouncement
    /// @dev Log-ordering invariant: the disclosure header appears before the closing marker,
    ///      with any inner-call events sandwiched in between. Critical for indexers that
    ///      pair open/close by adjacency.
    function test_announce_success_orderingHeaderBeforeFooter(string calldata id) public {
        _grantOperator();
        vm.recordLogs();
        _announce(operator, new bytes[](0), id, "desc", "uri");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 headerAt = _firstLogIndex(logs, IB20Asset.Announcement.selector);
        int256 footerAt = _firstLogIndex(logs, IB20Asset.EndAnnouncement.selector);
        assertGt(headerAt, -1, "Announcement must be present");
        assertGt(footerAt, -1, "EndAnnouncement must be present");
        assertLt(headerAt, footerAt, "Announcement must precede EndAnnouncement");
    }

    /// @notice Verifies the id-consumed bit is set BEFORE inner calls run
    /// @dev The order matters because a delegatecall back into announce (currently blocked by
    ///      _checkSelector) would also fail the id-consumed guard if it tried to reuse the id.
    ///      A failing inner call reverts everything, but a SUCCESSFUL announce must have
    ///      flipped the bit BEFORE inner-call execution, not after. We can't observe the
    ///      pre-inner ordering directly without hacks, but we can confirm the post-success
    ///      invariant: `isAnnouncementIdUsed(id)` is true at the end of the call.
    function test_announce_success_marksIdConsumed(string calldata id) public {
        _announce(id);
        assertTrue(asset().isAnnouncementIdUsed(id), "id must be marked consumed after success");
    }
}
