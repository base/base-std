// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title  PolicyRegistry composite-policy regression suite
///
/// @notice Composites (UNION / INTERSECT) were bolted onto a registry that already shipped: they
///         share the global policy counter, the ID encoding, the packed-policy slot, the event
///         surface, and the dispatcher with simple policies. This suite locks in the invariants
///         that adding them must NOT have disturbed — the things that are only observable when
///         both kinds coexist in the same registry.
///
/// @dev    Spec IDs cite `brains/composite_policy/SMOKE_TEST_SPECS.md`. Covered here:
///         - **R-1** — the shared counter stays contiguous across interleaved kinds.
///         - **R-7** — `MAX_BATCH_SIZE` (64 accounts) and `MAX_CHILD_POLICIES` (4 children) are
///           two independent limits and are never conflated in either direction.
///         - **EV-5 / R-5** — no `CompositePolicyCreated` event exists or is emitted.
///         - **CE-9** — no child-set getter exists on the ABI.
///
///         Tests that need a working composite surface open with `_skipIfNoComposite()`: composites
///         are a V2 (Cobalt) feature and the live lane still pins Beryl / V1, where the two
///         composite selectors do not resolve at all. The halves that only exercise the simple
///         surface (the 65-account batch limit) carry no guard and run in every lane.
contract PolicyRegistryCompositeRegressionsTest is PolicyRegistryTest {
    /// @dev Low 56 bits of a policy ID — the global counter value the ID consumed. The top byte is
    ///      the `PolicyType` discriminator and is deliberately masked off: the whole point of R-1
    ///      is that the counter advances identically regardless of which kind consumed it.
    uint64 internal constant POLICY_ID_COUNTER_MASK = uint64((1 << 56) - 1);

    /// @dev The counter portion of `policyId`.
    function _counterOf(uint64 policyId) internal pure returns (uint64) {
        return policyId & POLICY_ID_COUNTER_MASK;
    }

    /// @dev The `PolicyType` discriminator encoded in `policyId`'s top byte.
    function _typeByteOf(uint64 policyId) internal pure returns (uint8) {
        return uint8(policyId >> 56);
    }

    // ============================================================
    //           R-1 — ONE COUNTER, SHARED BY BOTH KINDS
    // ============================================================

    /// @notice Verifies interleaved simple and composite creates draw from a single contiguous counter
    ///
    /// @dev Spec R-1 (`SMOKE_TEST_SPECS.md` § Regressions) — "Interleaving composites and simple
    ///      policies does not disturb simple-policy ID assignment; counter stays contiguous across
    ///      both kinds." Also covers CC-8 ("creating a composite advances the shared policy counter
    ///      by exactly one").
    ///
    ///      Two assertions per create, and both matter:
    ///        1. the returned ID equals `_predictNextPolicyId(type)` read from the live counter
    ///           immediately before the call — pins the ID *encoding* (type byte | counter);
    ///        2. the counter portion is exactly one more than the previous create's, *whatever kind
    ///           produced it* — pins the ID *allocation*.
    ///
    ///      (2) is the assertion that catches a composite accidentally getting its own counter
    ///      space: a separate composite counter would still satisfy (1) for each kind in isolation
    ///      (each sequence would be internally contiguous) while silently colliding the low 56 bits
    ///      of a composite ID with a simple one, or leaving a gap in the simple sequence. Only the
    ///      interleaved walk makes that observable.
    ///
    ///      The child set is seeded ONCE, up front, and reused by both composites (legal per CC-7 —
    ///      children are referenced, not consumed). That keeps the four creates under test strictly
    ///      adjacent on the counter; seeding children between them would inject unrelated
    ///      allocations and make "+1" vacuous.
    function test_compositeCounter_success_sharedWithSimplePolicies(
        uint8 simpleIdxA,
        uint8 gateIdxA,
        uint8 simpleIdxB,
        uint8 gateIdxB
    ) public {
        _skipIfNoComposite();

        IPolicyRegistry.PolicyType simpleA = _creatablePolicyType(simpleIdxA);
        IPolicyRegistry.PolicyType gateA = _creatableCompositeType(gateIdxA);
        IPolicyRegistry.PolicyType simpleB = _creatablePolicyType(simpleIdxB);
        IPolicyRegistry.PolicyType gateB = _creatableCompositeType(gateIdxB);

        // Seeded before the interleave so the four creates under test are counter-adjacent.
        uint64[] memory children = _makeSimpleChildren(MIN_CHILD_POLICIES);

        // 1. simple
        uint64 predicted0 = _predictNextPolicyId(simpleA);
        uint64 id0 = policyRegistry.createPolicy(admin, simpleA);
        assertEq(id0, predicted0, "simple #1 must take the predicted id");

        // 2. composite
        uint64 predicted1 = _predictNextPolicyId(gateA);
        uint64 id1 = policyRegistry.createCompositePolicy(admin, gateA, children);
        assertEq(id1, predicted1, "composite #1 must take the predicted id");
        assertEq(_counterOf(id1), _counterOf(id0) + 1, "composite must consume the very next counter after a simple");

        // 3. simple — the create that a separate composite counter would knock out of sequence
        uint64 predicted2 = _predictNextPolicyId(simpleB);
        uint64 id2 = policyRegistry.createPolicy(admin, simpleB);
        assertEq(id2, predicted2, "simple #2 must take the predicted id");
        assertEq(_counterOf(id2), _counterOf(id1) + 1, "simple must consume the very next counter after a composite");

        // 4. composite
        uint64 predicted3 = _predictNextPolicyId(gateB);
        uint64 id3 = policyRegistry.createCompositePolicy(admin, gateB, children);
        assertEq(id3, predicted3, "composite #2 must take the predicted id");
        assertEq(_counterOf(id3), _counterOf(id2) + 1, "composite must consume the very next counter after a simple");

        // The counter advanced by exactly four across four creates: no kind skipped, doubled, or
        // reserved a range of its own.
        assertEq(
            _counterOf(id3), _counterOf(id0) + 3, "four interleaved creates must consume four consecutive counters"
        );

        // Each ID still carries its own type byte — contiguity is a property of the counter lane
        // only, not of the whole ID.
        assertEq(_typeByteOf(id0), uint8(simpleA), "simple #1 type byte");
        assertEq(_typeByteOf(id1), uint8(gateA), "composite #1 type byte");
        assertEq(_typeByteOf(id2), uint8(simpleB), "simple #2 type byte");
        assertEq(_typeByteOf(id3), uint8(gateB), "composite #2 type byte");

        // All four are live, distinct policies.
        assertTrue(policyRegistry.policyExists(id0), "simple #1 must exist");
        assertTrue(policyRegistry.policyExists(id1), "composite #1 must exist");
        assertTrue(policyRegistry.policyExists(id2), "simple #2 must exist");
        assertTrue(policyRegistry.policyExists(id3), "composite #2 must exist");
        assertTrue(
            id0 != id1 && id1 != id2 && id2 != id3 && id0 != id2 && id1 != id3 && id0 != id3, "ids must be distinct"
        );
    }

    // ============================================================
    //      R-7 — MAX_BATCH_SIZE (64) vs MAX_CHILD_POLICIES (4)
    // ============================================================

    /// @notice Verifies the 64-account batch limit is the account limit, and only the account limit
    ///
    /// @dev Spec R-7 (`SMOKE_TEST_SPECS.md` § Regressions) — "`MAX_BATCH_SIZE` (64 accounts) and
    ///      `MAX_CHILD_POLICIES` (4 children) are never conflated; 65 accounts →
    ///      `BatchSizeTooLarge(64)`."
    ///
    ///      Two directions:
    ///        - 65 accounts on `createPolicyWithAccounts` reverts with `BatchSizeTooLarge(64)` —
    ///          the account cap is still 64, not narrowed toward the composite child cap;
    ///        - a simple policy with 5 accounts (one past `MAX_CHILD_POLICIES`) succeeds and the
    ///          members are all live — the 4-child composite cap did not leak onto the simple
    ///          membership path.
    ///
    ///      No composite guard: this half only touches the simple surface, so it is meaningful on
    ///      Beryl / V1 too.
    function test_batchSizeLimit_revert_unaffectedByChildPolicyCap(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));

        // Over the account cap by exactly one.
        address[] memory tooManyAccounts = _makeAccounts(MAX_BATCH_SIZE + 1);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE));
        vm.prank(caller);
        policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, tooManyAccounts);

        // Comfortably over the CHILD cap (4) but far under the ACCOUNT cap (64): must succeed.
        // If the two limits were conflated this would revert with `ChildPoliciesOutsideOfRange`.
        address[] memory fiveAccounts = _makeAccounts(MAX_CHILD_POLICIES + 1);
        vm.prank(caller);
        uint64 policyId =
            policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, fiveAccounts);
        assertTrue(policyRegistry.policyExists(policyId), "5-account simple policy must be created");
        for (uint256 i = 0; i < fiveAccounts.length; ++i) {
            assertTrue(policyRegistry.isAuthorized(policyId, fiveAccounts[i]), "every seeded account must be a member");
        }

        // And the account cap itself is inclusive at 64 — the boundary did not move.
        address[] memory atCap = _makeAccounts(MAX_BATCH_SIZE);
        vm.prank(caller);
        uint64 atCapId = policyRegistry.createPolicyWithAccounts(admin_, IPolicyRegistry.PolicyType.ALLOWLIST, atCap);
        assertTrue(policyRegistry.policyExists(atCapId), "64-account simple policy must be created");
    }

    /// @notice Verifies the 4-child composite cap is the child cap, and is not the 64-account cap
    ///
    /// @dev Spec R-7 (`SMOKE_TEST_SPECS.md` § Regressions) — "5 children →
    ///      `ChildPoliciesOutsideOfRange(2,4)`."
    ///
    ///      Two directions:
    ///        - 5 children reverts with `ChildPoliciesOutsideOfRange(2, 4)` and explicitly NOT with
    ///          `BatchSizeTooLarge(64)`. Five is far below 64, so a composite governed by the
    ///          account cap would happily accept it — this is what proves the composite path is
    ///          NOT subject to the 64 limit but to its own, tighter one;
    ///        - 4 children (the inclusive cap) succeeds, bracketing the boundary.
    function test_childPolicyCap_revert_unaffectedByBatchSizeLimit(address caller, address admin_, uint8 gateIdx)
        public
    {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType gate = _creatableCompositeType(gateIdx);

        // One past the child cap — and nowhere near the 64-account cap.
        uint64[] memory fiveChildren = _makeSimpleChildren(MAX_CHILD_POLICIES + 1);
        vm.prank(caller);
        (bool ok, bytes memory ret) = address(policyRegistry)
            .call(abi.encodeCall(IPolicyRegistry.createCompositePolicy, (admin_, gate, fiveChildren)));
        assertFalse(ok, "5 children must revert");
        assertEq(
            ret,
            abi.encodeWithSelector(
                IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
            ),
            "5 children must revert with ChildPoliciesOutsideOfRange(2, 4)"
        );
        assertTrue(
            keccak256(ret)
                != keccak256(abi.encodeWithSelector(IPolicyRegistry.BatchSizeTooLarge.selector, MAX_BATCH_SIZE)),
            "the child-count limit must not be reported as the account-batch limit"
        );

        // At the child cap: succeeds. Bracketing 4 (ok) / 5 (revert) pins the cap at 4, not 64.
        uint64[] memory fourChildren = _makeSimpleChildren(MAX_CHILD_POLICIES);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createCompositePolicy(admin_, gate, fourChildren);
        assertTrue(policyRegistry.policyExists(policyId), "4-child composite must be created");
    }

    // ============================================================
    //     EV-5 / CE-9 — SELECTOR- AND EVENT-ABSENCE ASSERTIONS
    // ============================================================
    //
    // The two assertions below lock in a deliberate design decision rather than an implementation
    // detail, so that ADDING either surface later is a conscious, reviewed change rather than an
    // accident:
    //
    //   1. Composites reuse the canonical `PolicyCreated` event. There is no
    //      `CompositePolicyCreated`. Every existing `PolicyCreated` consumer (indexers, subgraphs,
    //      the smoke lane's event scraper) therefore sees composites for free, with no ABI update.
    //      Introducing a dedicated creation event would silently split that stream in two and
    //      strand consumers that only watch the canonical one.
    //
    //   2. A composite's child set is NOT readable through the ABI. It is observable only via the
    //      `CompositePolicyUpdated` event stream (EV-12) or raw storage. That is intentional: the
    //      child set is unbounded-ish return data on a precompile ABI, and every consumer that
    //      needs it can reconstruct it from the last event. Adding a getter is a real API
    //      commitment (return-shape, gas, and V1/V2 divergence surface), not a convenience.
    //
    // Both are written as ABSENCE assertions in the style of `test/regression/B20Removals.t.sol`:
    // args are irrelevant, because dispatch fails before decoding for an unknown selector.

    /// @dev Asserts a low-level call of `callData` to the registry does not resolve.
    function _assertSelectorAbsent(bytes memory callData, string memory err) internal {
        (bool ok,) = address(policyRegistry).call(callData);
        assertFalse(ok, err);
    }

    /// @notice Verifies no `CompositePolicyCreated` event exists or is emitted on composite creation
    ///
    /// @dev Specs EV-5 and R-5 (`SMOKE_TEST_SPECS.md` § EV — Events / § Regressions) — "No
    ///      `CompositePolicyCreated` event exists or is emitted; composites reuse the canonical
    ///      `PolicyCreated`."
    ///
    ///      The topic0 is computed from the literal signature string rather than from a Solidity
    ///      `event` declaration: declaring the event here — even just to reference `.selector` —
    ///      would be the very thing this test forbids, and would make the assertion pass trivially
    ///      against a locally-declared type instead of the shipped ABI. The hash is therefore the
    ///      historical/plausible signature, computed by hand.
    ///
    ///      Positive control included: `PolicyCreated` MUST be present in the same capture, so a
    ///      composite create that emitted nothing at all could not pass this test vacuously.
    function test_createCompositePolicy_success_noCompositePolicyCreatedEvent(
        address caller,
        address admin_,
        uint8 gateIdx
    ) public {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType gate = _creatableCompositeType(gateIdx);

        uint64[] memory children = _makeSimpleChildren(MIN_CHILD_POLICIES);

        bytes32 forbiddenTopic = keccak256("CompositePolicyCreated(uint64,address,uint64[])");

        vm.recordLogs();
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, gate, children);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _firstLogIndex(logs, forbiddenTopic),
            -1,
            "no CompositePolicyCreated event may be emitted - composites reuse PolicyCreated"
        );

        // Positive control: the canonical creation event IS the one composites emit.
        assertGt(
            _firstLogIndex(logs, IPolicyRegistry.PolicyCreated.selector),
            -1,
            "composite creation must emit the canonical PolicyCreated"
        );
        // ...and the child set is carried by the update event, which is the only ABI-visible source
        // of it (pairs with CE-9 below).
        assertGt(
            _firstLogIndex(logs, IPolicyRegistry.CompositePolicyUpdated.selector),
            -1,
            "composite creation must emit CompositePolicyUpdated"
        );
    }

    /// @notice Verifies no child-set getter resolves on the registry surface
    ///
    /// @dev Spec CE-9 (`SMOKE_TEST_SPECS.md` § CE — Evaluation semantics) — "Nobody can observe a
    ///      composite's child set through the ABI. No getter exists — children are readable only
    ///      via `CompositePolicyUpdated` or raw storage."
    ///
    ///      Probes the plausible spellings a future getter would most likely take. A real, live
    ///      composite is created first so the probes are not vacuous: if any of these selectors
    ///      existed, this ID is exactly the argument that would make it return successfully.
    ///
    ///      A failure here is not necessarily a bug — it means someone added a child-set getter.
    ///      That is a deliberate API change and should be reviewed as one, not silently absorbed by
    ///      deleting the probe.
    function test_childPolicies_revert_noChildSetGetter(uint8 gateIdx) public {
        _skipIfNoComposite();
        IPolicyRegistry.PolicyType gate = _creatableCompositeType(gateIdx);
        uint64 compositeId = _createComposite(gate, MIN_CHILD_POLICIES);
        assertTrue(policyRegistry.policyExists(compositeId), "composite must exist for the probes to be meaningful");

        _assertSelectorAbsent(
            abi.encodeWithSignature("childPolicies(uint64)", compositeId), "childPolicies(uint64) must not resolve"
        );
        _assertSelectorAbsent(
            abi.encodeWithSignature("getChildPolicies(uint64)", compositeId),
            "getChildPolicies(uint64) must not resolve"
        );
        _assertSelectorAbsent(
            abi.encodeWithSignature("compositeChildren(uint64)", compositeId),
            "compositeChildren(uint64) must not resolve"
        );
        // Two more spellings a public storage array / mapping would auto-generate.
        _assertSelectorAbsent(
            abi.encodeWithSignature("children(uint64)", compositeId), "children(uint64) must not resolve"
        );
        _assertSelectorAbsent(
            abi.encodeWithSignature("childPolicies(uint64,uint256)", compositeId, uint256(0)),
            "childPolicies(uint64,uint256) must not resolve"
        );
    }
}
