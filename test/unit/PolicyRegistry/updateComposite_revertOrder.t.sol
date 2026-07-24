// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `updateComposite`.
///
/// @notice **Canonical order:**
///         1. POLICY-NOT-FOUND (composite `policyId` does not exist) → `PolicyNotFound`
///         2. INCOMPATIBLE-TYPE (`policyId` is a simple policy) → `IncompatiblePolicyType`
///         3. UNAUTHORIZED (caller is not the admin) → `Unauthorized`
///         4. COUNT-OUTSIDE-RANGE (`childPolicyIds.length` not in `[2, 4]`) → `ChildPoliciesOutsideOfRange(2, 4)`
///         5. CHILD-NOT-FOUND (a child does not exist) → `PolicyNotFound`
///         6. INVALID-CHILD (a child is itself a composite) → `InvalidChildPolicy`
///
///         Walks from all conditions broken to success, fixing one per step. `PolicyNotFound`
///         appears twice: for the composite itself (step 1) and for a child (step 5).
contract PolicyRegistryUpdateCompositeRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_updateComposite_revertOrder(uint8 typeIdx) public {
        IPolicyRegistry.PolicyType gate = _creatableCompositeType(typeIdx);

        // Fixtures.
        // Two existing simple policies double as the composite's seed children and the valid
        // replacement children used at the end of the walk.
        uint64[] memory validSimple = _makeSimpleChildren(2);
        uint64 composite = _createComposite(bob, alice, gate, validSimple); // admin = alice
        uint64 simpleId = policyRegistry.createPolicy(alice, IPolicyRegistry.PolicyType.ALLOWLIST); // exists, simple
        uint64 otherComposite = _createComposite(IPolicyRegistry.PolicyType.INTERSECT, 2); // composite child

        // Ghost (well-formed, never-created) IDs at counters far above anything created.
        uint64 ghostComposite = (uint64(uint8(IPolicyRegistry.PolicyType.UNION)) << 56) | uint64(3_000_000);
        uint64 ghostChild = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(2_000_000);
        uint64[] memory tooManyGhosts = new uint64[](MAX_CHILD_POLICIES + 1); // 5, all nonexistent
        for (uint256 i = 0; i < tooManyGhosts.length; ++i) {
            tooManyGhosts[i] = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(1_000_000 + i);
        }

        // 1. POLICY-NOT-FOUND (self): composite never created, called by a non-admin, oversized child set.
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateComposite(ghostComposite, tooManyGhosts);

        // Fix: target an existing policy — but a simple one (wrong type).

        // 2. INCOMPATIBLE-TYPE: target exists but is simple; fires before the auth check.
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.updateComposite(simpleId, tooManyGhosts);

        // Fix: target the composite (correct type); attacker is still not its admin.

        // 3. UNAUTHORIZED: composite, but caller is not the admin (alice); fires before the count/size checks.
        vm.prank(attacker);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.updateComposite(composite, tooManyGhosts);

        // Fix: call as the admin (alice).

        // 4. COUNT-OUTSIDE-RANGE: admin, but a child count outside [2, 4] (all nonexistent); fires
        //    before the existence check. Exercises both the under-range (1 child) and over-range
        //    (> MAX_CHILD_POLICIES) ends.
        bytes memory outsideRange = abi.encodeWithSelector(
            IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
        );
        uint64[] memory one = new uint64[](1);
        one[0] = ghostChild;
        vm.prank(alice);
        vm.expectRevert(outsideRange);
        policyRegistry.updateComposite(composite, one);

        vm.prank(alice);
        vm.expectRevert(outsideRange);
        policyRegistry.updateComposite(composite, tooManyGhosts);

        // Fix: bring the child count within [2, 4].

        // 5. CHILD-NOT-FOUND: in-range child set, but one child never existed; fires before the
        //    simple-vs-composite check.
        vm.prank(alice);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateComposite(composite, _childIds(ghostChild, otherComposite));

        // Fix: replace the ghost with an existing simple policy.

        // 6. INVALID-CHILD: all children exist, but one is itself a composite → InvalidChildPolicy.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, otherComposite));
        policyRegistry.updateComposite(composite, _childIds(validSimple[0], otherComposite));

        // Fix: replace the composite child with a simple policy.

        // Success.
        vm.prank(alice);
        policyRegistry.updateComposite(composite, _childIds(validSimple[0], validSimple[1]));
    }
}
