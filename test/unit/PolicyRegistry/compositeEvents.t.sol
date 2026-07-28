// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @notice Event-surface tests for composite policies (UNION / INTERSECT).
///
/// Where `createCompositePolicy.t.sol` and `updateComposite.t.sol` pin the
/// *state* transitions (and use `vm.expectEmit` for the happy-path event
/// shape), this file pins the *log stream* itself: how many
/// `CompositePolicyUpdated` records a call produces, in what order relative
/// to the other registry events, what the decoded `uint64[]` payload
/// contains, and — just as important — which calls emit nothing at all.
///
/// Every test opens with `_skipIfNoComposite()`: composites are a
/// `PolicyRegistry` V2 feature and the live Beryl/V1 precompile rejects both
/// composite selectors before routing, so the whole file must self-skip
/// there. In REFERENCE mode the probe is a no-op and everything runs.
contract PolicyRegistryCompositeEventsTest is PolicyRegistryTest {
    // ============================================================
    //                        CREATION ORDERING
    // ============================================================

    /// @notice Verifies creating a composite emits exactly PolicyCreated -> PolicyAdminUpdated ->
    ///         CompositePolicyUpdated, in that order and nothing else
    /// @dev EV-1. The three records are a single logical "composite born" frame and consumers
    ///      (indexers reconstructing the policy graph) rely on the child set arriving after the
    ///      policy itself exists. Asserting strictly increasing `_firstLogIndex` values pins the
    ///      order; asserting `logs.length == 3` pins that nothing extra leaks into the frame.
    function test_createCompositePolicy_success_emitsThreeEventsInOrder(address caller, address admin_, uint8 typeIdx)
        public
    {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);

        // Seed the children (and lazily initialize the built-ins) BEFORE recording, so the
        // capture window contains only the composite create.
        uint64[] memory children = _makeSimpleChildren(MIN_CHILD_POLICIES);

        vm.recordLogs();
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3, "composite creation must emit exactly three events");

        int256 createdIdx = _firstLogIndex(logs, IPolicyRegistry.PolicyCreated.selector);
        int256 adminIdx = _firstLogIndex(logs, IPolicyRegistry.PolicyAdminUpdated.selector);
        int256 compositeIdx = _firstLogIndex(logs, IPolicyRegistry.CompositePolicyUpdated.selector);

        assertGt(createdIdx, -1, "PolicyCreated must be emitted");
        assertGt(adminIdx, -1, "PolicyAdminUpdated must be emitted");
        assertGt(compositeIdx, -1, "CompositePolicyUpdated must be emitted");

        assertLt(createdIdx, adminIdx, "PolicyCreated must precede PolicyAdminUpdated");
        assertLt(adminIdx, compositeIdx, "PolicyAdminUpdated must precede CompositePolicyUpdated");
    }

    // ============================================================
    //                       UPDATE PAYLOAD
    // ============================================================

    /// @notice Verifies a successful updateComposite emits exactly one CompositePolicyUpdated
    /// @dev EV-6. The event is the sole wire signal that a composite's child set moved; a second
    ///      copy (e.g. one per child, or a pre/post pair) would make naive indexers double-apply.
    ///      Counts matching records rather than using `vm.expectEmit`, which only asserts presence.
    function test_updateComposite_success_emitsExactlyOneCompositePolicyUpdated(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), MIN_CHILD_POLICIES);
        uint64[] memory newChildren = _makeSimpleChildren(MIN_CHILD_POLICIES);

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateComposite(composite, newChildren);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            1,
            "updateComposite must emit exactly one CompositePolicyUpdated"
        );
    }

    /// @notice Verifies replacing [a,b] with [c,d] emits a payload of exactly [c,d]
    /// @dev EV-7. The event carries the complete POST-update set, never a delta and never a union
    ///      with the prior set. Decodes the non-indexed `uint64[]` out of `log.data` and asserts
    ///      element-by-element that the outgoing children are absent.
    function test_updateComposite_success_emitsOnlyNewChildren(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 a = _createAllowlist();
        uint64 b = _createAllowlist();
        uint64 composite = _createComposite(address(this), admin, _creatableCompositeType(typeIdx), _childIds(a, b));

        uint64 c = _createAllowlist();
        uint64 d = _createAllowlist();

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateComposite(composite, _childIds(c, d));
        uint64[] memory emitted = _lastCompositeChildren(vm.getRecordedLogs());

        assertEq(emitted.length, 2, "payload must carry exactly the two new children");
        assertEq(emitted[0], c, "payload[0] must be the first new child");
        assertEq(emitted[1], d, "payload[1] must be the second new child");
        assertFalse(_contains(emitted, a), "outgoing child a must not appear in the payload");
        assertFalse(_contains(emitted, b), "outgoing child b must not appear in the payload");
    }

    /// @notice Verifies shrinking a composite from 4 children to 2 emits exactly 2 entries
    /// @dev EV-8. Guards against a stale tail: a storage array written in place without a length
    ///      reset (or an event assembled from a fixed-size buffer) would leak the 3rd and 4th
    ///      entries of the previous set into the payload.
    function test_updateComposite_success_emitsFullSetOnShrink(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64[] memory four = _makeSimpleChildren(MAX_CHILD_POLICIES);
        uint64 composite = _createComposite(address(this), admin, _creatableCompositeType(typeIdx), four);

        uint64[] memory two = _makeSimpleChildren(MIN_CHILD_POLICIES);

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateComposite(composite, two);
        uint64[] memory emitted = _lastCompositeChildren(vm.getRecordedLogs());

        assertEq(emitted.length, MIN_CHILD_POLICIES, "shrink must emit exactly the new, shorter set");
        assertEq(emitted[0], two[0], "payload[0] must be the first surviving child");
        assertEq(emitted[1], two[1], "payload[1] must be the second surviving child");
        for (uint256 i = 0; i < four.length; ++i) {
            assertFalse(_contains(emitted, four[i]), "no entry from the longer previous set may survive");
        }
    }

    /// @notice Verifies growing a composite from 2 children to 4 emits all 4 in the supplied order
    /// @dev EV-9. The payload is order-preserving with respect to the caller's array — consumers
    ///      that hash or diff the child list positionally depend on the registry not sorting or
    ///      de-duplicating it on the way out.
    function test_updateComposite_success_emitsFullSetOnGrow(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), MIN_CHILD_POLICIES);
        uint64[] memory four = _makeSimpleChildren(MAX_CHILD_POLICIES);

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateComposite(composite, four);
        uint64[] memory emitted = _lastCompositeChildren(vm.getRecordedLogs());

        assertEq(emitted.length, MAX_CHILD_POLICIES, "grow must emit the full, longer set");
        for (uint256 i = 0; i < four.length; ++i) {
            assertEq(emitted[i], four[i], "payload must preserve the supplied child order");
        }
    }

    /// @notice Verifies a no-op update re-supplying the identical child set still emits
    /// @dev EV-11. Emission is unconditional on success, not diffed against prior state. A registry
    ///      that suppressed "unchanged" writes would silently drop the audit record of an admin
    ///      exercising their update authority, so the no-op case is a required emission, not an
    ///      accident.
    function test_updateComposite_success_emitsOnNoOpUpdate(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 a = _createAllowlist();
        uint64 b = _createAllowlist();
        uint64 composite = _createComposite(address(this), admin, _creatableCompositeType(typeIdx), _childIds(a, b));

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateComposite(composite, _childIds(a, b));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            1,
            "an identical-set update must still emit exactly one CompositePolicyUpdated"
        );

        uint64[] memory emitted = _lastCompositeChildren(logs);
        assertEq(emitted.length, 2, "no-op payload must still carry the full set");
        assertEq(emitted[0], a, "no-op payload[0] must be the unchanged first child");
        assertEq(emitted[1], b, "no-op payload[1] must be the unchanged second child");
    }

    /// @notice Verifies the LAST CompositePolicyUpdated after N sequential updates reconstructs the
    ///         live child set
    /// @dev EV-12. An indexer that keeps only the most recent record per `policyId` must end up
    ///      with the registry's actual state — i.e. the log stream is last-write-wins, with no
    ///      out-of-order or trailing emission. "Current" is proven behaviorally rather than by
    ///      re-reading the event: a member added to one of the FINAL children authorizes under the
    ///      composite, while a member of a superseded child does not.
    function test_updateComposite_success_lastEventReflectsCurrentChildSet() public {
        _skipIfNoComposite();
        // UNION so that membership in any single live child is sufficient to authorize.
        uint64 composite = _createComposite(IPolicyRegistry.PolicyType.UNION, MIN_CHILD_POLICIES);

        uint64[] memory firstSet = _makeSimpleChildren(MIN_CHILD_POLICIES);
        uint64[] memory secondSet = _makeSimpleChildren(MAX_CHILD_POLICIES);
        uint64[] memory finalSet = _makeSimpleChildren(MIN_CHILD_POLICIES + 1);

        vm.recordLogs();
        vm.startPrank(admin);
        policyRegistry.updateComposite(composite, firstSet);
        policyRegistry.updateComposite(composite, secondSet);
        policyRegistry.updateComposite(composite, finalSet);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            3,
            "three sequential updates must produce three records"
        );

        uint64[] memory emitted = _lastCompositeChildren(logs);
        assertEq(emitted.length, finalSet.length, "last record must carry the final set length");
        for (uint256 i = 0; i < finalSet.length; ++i) {
            assertEq(emitted[i], finalSet[i], "last record must reconstruct the final child set");
        }

        // Behavioral proof that the decoded set is the LIVE one: alice joins a child named by the
        // last record and is authorized; bob joins a superseded child and is not.
        address[] memory aliceOnly = new address[](1);
        aliceOnly[0] = alice;
        address[] memory bobOnly = new address[](1);
        bobOnly[0] = bob;

        vm.startPrank(admin);
        policyRegistry.updateAllowlist(emitted[0], true, aliceOnly);
        policyRegistry.updateAllowlist(secondSet[0], true, bobOnly);
        vm.stopPrank();

        assertTrue(
            policyRegistry.isAuthorized(composite, alice), "member of a child named by the last record must authorize"
        );
        assertFalse(
            policyRegistry.isAuthorized(composite, bob), "member of a superseded child must no longer authorize"
        );
    }

    // ============================================================
    //                    NEGATIVE / CROSS-CUTTING
    // ============================================================

    /// @notice Verifies reverting composite calls emit no CompositePolicyUpdated
    /// @dev EV-13. Covers three distinct rejection points — zero admin on create (entry guard),
    ///      unauthorized update (auth guard), and an out-of-range child count (arity guard). All
    ///      three must be log-silent: a listener may never observe a child-set change that did not
    ///      happen. Every fixture is built before `vm.recordLogs()` so the capture window contains
    ///      only the reverting calls. Note that `vm.expectRevert` and `vm.recordLogs` compose: the
    ///      cheatcode consumes the revert and the recorder keeps collecting across the calls.
    function test_updateComposite_revert_emitsNothing(uint8 typeIdx, uint8 overflow) public {
        _skipIfNoComposite();
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);

        uint64 composite = _createComposite(pt, MIN_CHILD_POLICIES);
        uint64[] memory validChildren = _makeSimpleChildren(MIN_CHILD_POLICIES);
        uint64[] memory tooMany = _makeSimpleChildren(MAX_CHILD_POLICIES + 1 + (uint256(overflow) % 4)); // 5..8

        vm.recordLogs();

        // (1) Create with a zero admin.
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        policyRegistry.createCompositePolicy(address(0), pt, validChildren);

        // (2) Update from a non-admin.
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(attacker);
        policyRegistry.updateComposite(composite, validChildren);

        // (3) Update with a child count above MAX_CHILD_POLICIES.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
            )
        );
        vm.prank(admin);
        policyRegistry.updateComposite(composite, tooMany);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            0,
            "a reverting composite call must not emit CompositePolicyUpdated"
        );
        assertEq(logs.length, 0, "a reverting composite call must not emit anything at all");
    }

    /// @notice Verifies createPolicy never emits CompositePolicyUpdated
    /// @dev EV-14. Simple-policy constructors have no child set, so the composite event must not
    ///      appear on their path — otherwise an indexer would materialize a phantom composite node
    ///      (with an empty or garbage child list) for every ALLOWLIST/BLOCKLIST ever created.
    function test_createPolicy_success_emitsNoCompositePolicyUpdated(address caller, address admin_, uint8 typeIdx)
        public
    {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));

        vm.recordLogs();
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, _creatablePolicyType(typeIdx));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            0,
            "createPolicy must not emit CompositePolicyUpdated"
        );
    }

    /// @notice Verifies createPolicyWithAccounts never emits CompositePolicyUpdated
    /// @dev EV-14. Same invariant as `createPolicy`, on the seeded-membership constructor: the
    ///      extra AllowlistUpdated/BlocklistUpdated record must not be joined by a composite one.
    function test_createPolicyWithAccounts_success_emitsNoCompositePolicyUpdated(
        address caller,
        address admin_,
        uint8 typeIdx
    ) public {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        address[] memory accounts = _makeAccounts(3);

        vm.recordLogs();
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, _creatablePolicyType(typeIdx), accounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            0,
            "createPolicyWithAccounts must not emit CompositePolicyUpdated"
        );
    }

    /// @notice Verifies editing a child allowlist emits against the CHILD id and nothing against the
    ///         composite, even though the composite's verdict flips
    /// @dev EV-15. Composite authorization is derived, not stored: the composite has no state of
    ///      its own to change when a child's membership moves, so it must stay log-silent. Asserts
    ///      both halves — AllowlistUpdated carries the child's ID in topic1, and no recorded log
    ///      carries the composite's ID in ANY topic — while `isAuthorized` on the composite flips
    ///      false -> true across the same call.
    function test_updateAllowlist_success_emitsAgainstChildNotComposite() public {
        _skipIfNoComposite();
        uint64 childA = _createAllowlist();
        uint64 childB = _createAllowlist();
        uint64 composite =
            _createComposite(address(this), admin, IPolicyRegistry.PolicyType.UNION, _childIds(childA, childB));

        assertFalse(policyRegistry.isAuthorized(composite, alice), "alice must start unauthorized under the union");

        address[] memory aliceOnly = new address[](1);
        aliceOnly[0] = alice;

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateAllowlist(childA, true, aliceOnly);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Half 1: the child event fires, keyed on the CHILD's policy ID.
        int256 idx = _firstLogIndex(logs, IPolicyRegistry.AllowlistUpdated.selector);
        assertGt(idx, -1, "AllowlistUpdated must be emitted for the child");
        assertEq(
            logs[uint256(idx)].topics[1],
            bytes32(uint256(childA)),
            "AllowlistUpdated topic1 must be the child's policy ID"
        );

        // Half 2: nothing anywhere in the stream references the composite.
        assertFalse(_anyTopicMentions(logs, composite), "no log may reference the composite's policy ID");
        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            0,
            "a child membership edit must not emit CompositePolicyUpdated"
        );

        // The derived verdict nonetheless flipped.
        assertTrue(policyRegistry.isAuthorized(composite, alice), "union verdict must flip once alice joins child A");
    }

    /// @notice Verifies editing a child blocklist emits against the CHILD id and nothing against the
    ///         composite, even though the composite's verdict flips
    /// @dev EV-15, blocklist half. INTERSECT over a blocklist and an allowlist: alice is allowlisted
    ///      and unblocked, so the gate authorizes her; blocking her in the child flips the composite
    ///      to false while emitting only BlocklistUpdated keyed on the child's ID.
    function test_updateBlocklist_success_emitsAgainstChildNotComposite() public {
        _skipIfNoComposite();
        uint64 blockChild = _createBlocklist();
        uint64 allowChild = _createAllowlist();
        uint64 composite = _createComposite(
            address(this), admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(blockChild, allowChild)
        );

        address[] memory aliceOnly = new address[](1);
        aliceOnly[0] = alice;
        vm.prank(admin);
        policyRegistry.updateAllowlist(allowChild, true, aliceOnly);
        assertTrue(policyRegistry.isAuthorized(composite, alice), "alice must start authorized under the intersect");

        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.updateBlocklist(blockChild, true, aliceOnly);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Half 1: the child event fires, keyed on the CHILD's policy ID.
        int256 idx = _firstLogIndex(logs, IPolicyRegistry.BlocklistUpdated.selector);
        assertGt(idx, -1, "BlocklistUpdated must be emitted for the child");
        assertEq(
            logs[uint256(idx)].topics[1],
            bytes32(uint256(blockChild)),
            "BlocklistUpdated topic1 must be the child's policy ID"
        );

        // Half 2: nothing anywhere in the stream references the composite.
        assertFalse(_anyTopicMentions(logs, composite), "no log may reference the composite's policy ID");
        assertEq(
            _countLogs(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            0,
            "a child membership edit must not emit CompositePolicyUpdated"
        );

        // The derived verdict nonetheless flipped.
        assertFalse(
            policyRegistry.isAuthorized(composite, alice),
            "intersect verdict must flip once alice is blocked in a child"
        );
    }

    /// @notice Verifies stageUpdateAdmin on a composite emits PolicyAdminStaged, including on
    ///         overwrite and on clear
    /// @dev EV-17. Admin rotation is type-agnostic: a composite is administered exactly like a
    ///      simple policy, so all three staging transitions (nominate, re-nominate over a live
    ///      nomination, clear with `address(0)`) must produce one record each with the new pending
    ///      admin in topic3. The clear case is the easy one to get wrong — a registry that
    ///      suppressed the zero-address emission would leave indexers showing a stale nomination.
    function test_stageUpdateAdmin_success_emitsOnCompositeIncludingOverwriteAndClear(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), MIN_CHILD_POLICIES);

        // (1) Initial nomination.
        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, alice);
        _assertSoleAdminStaged(vm.getRecordedLogs(), composite, admin, alice, "initial nomination");
        assertEq(policyRegistry.pendingPolicyAdmin(composite), alice, "alice must be staged");

        // (2) Overwrite a live nomination.
        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, bob);
        _assertSoleAdminStaged(vm.getRecordedLogs(), composite, admin, bob, "overwriting nomination");
        assertEq(policyRegistry.pendingPolicyAdmin(composite), bob, "bob must replace alice as staged");

        // (3) Clear with address(0).
        vm.recordLogs();
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, address(0));
        _assertSoleAdminStaged(vm.getRecordedLogs(), composite, admin, address(0), "clearing nomination");
        assertEq(policyRegistry.pendingPolicyAdmin(composite), address(0), "nomination must be cleared");
    }

    // ============================================================
    //                        LOCAL HELPERS
    // ============================================================

    /// @notice Number of logs in `logs` whose `topics[0]` equals `sig`.
    /// @dev    Complements `BaseTest._firstLogIndex`, which answers "was it emitted / in what
    ///         order" but cannot distinguish one record from several.
    function _countLogs(Vm.Log[] memory logs, bytes32 sig) private pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    /// @notice Decodes the `uint64[] childPolicyIds` payload of the LAST `CompositePolicyUpdated`
    ///         record in `logs`. Reverts the test if there is none.
    /// @dev    `childPolicyIds` is the only non-indexed parameter, so `log.data` is exactly its
    ///         ABI head+tail encoding. Taking the LAST match (rather than the first) is what makes
    ///         the multi-update reconstruction test meaningful.
    function _lastCompositeChildren(Vm.Log[] memory logs) private pure returns (uint64[] memory) {
        bool found;
        bytes memory data;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == IPolicyRegistry.CompositePolicyUpdated.selector) {
                data = logs[i].data;
                found = true;
            }
        }
        require(found, "no CompositePolicyUpdated log recorded");
        return abi.decode(data, (uint64[]));
    }

    /// @notice Whether `ids` contains `needle`.
    function _contains(uint64[] memory ids, uint64 needle) private pure returns (bool) {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (ids[i] == needle) return true;
        }
        return false;
    }

    /// @notice Whether ANY topic of ANY log in `logs` equals `policyId` widened to a topic word.
    /// @dev    Policy IDs are the indexed key on every registry event, so scanning all topics (not
    ///         just topic1) is the strongest available "this policy is not mentioned" assertion.
    function _anyTopicMentions(Vm.Log[] memory logs, uint64 policyId) private pure returns (bool) {
        bytes32 needle = bytes32(uint256(policyId));
        for (uint256 i = 0; i < logs.length; ++i) {
            for (uint256 j = 0; j < logs[i].topics.length; ++j) {
                if (logs[i].topics[j] == needle) return true;
            }
        }
        return false;
    }

    /// @notice Asserts `logs` holds exactly one `PolicyAdminStaged` with the given indexed args.
    function _assertSoleAdminStaged(
        Vm.Log[] memory logs,
        uint64 policyId,
        address currentAdmin,
        address pendingAdmin,
        string memory label
    ) private {
        assertEq(
            _countLogs(logs, IPolicyRegistry.PolicyAdminStaged.selector),
            1,
            string.concat(label, ": exactly one PolicyAdminStaged expected")
        );
        int256 idx = _firstLogIndex(logs, IPolicyRegistry.PolicyAdminStaged.selector);
        Vm.Log memory log = logs[uint256(idx)];
        assertEq(log.topics[1], bytes32(uint256(policyId)), string.concat(label, ": topic1 must be the composite ID"));
        assertEq(
            log.topics[2], bytes32(uint256(uint160(currentAdmin))), string.concat(label, ": topic2 must be the admin")
        );
        assertEq(
            log.topics[3],
            bytes32(uint256(uint160(pendingAdmin))),
            string.concat(label, ": topic3 must be the new pending admin")
        );
    }
}
