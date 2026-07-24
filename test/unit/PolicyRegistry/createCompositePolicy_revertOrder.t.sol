// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title Sequential revert-order test for `createCompositePolicy`.
///
/// @notice **Canonical order:**
///         1. ZERO-ADMIN (`admin == address(0)`) → `ZeroAddress`
///         2. INCOMPATIBLE-TYPE (`policyType` not UNION/INTERSECT) → `IncompatiblePolicyType`
///         3. COUNT-OUTSIDE-RANGE (`childPolicyIds.length` not in `[2, 4]`) → `ChildPoliciesOutsideOfRange(2, 4)`
///         4. CHILD-NOT-FOUND (a child does not exist) → `PolicyNotFound`
///         5. INVALID-CHILD (a child is itself a composite) → `InvalidChildPolicy`
///
///         Walks from all conditions broken to success, fixing one per step. ZeroAddress-first
///         precedence mirrors `createPolicy` / `createPolicyWithAccounts`.
contract PolicyRegistryCreateCompositePolicyRevertOrderTest is PolicyRegistryTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_createCompositePolicy_revertOrder(uint8 typeIdx) public {
        IPolicyRegistry.PolicyType composite = _creatableCompositeType(typeIdx);

        // Fixtures.
        uint64 validSimpleA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 validSimpleB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        uint64 compositeChild = _createComposite(IPolicyRegistry.PolicyType.UNION, 2);

        // Ghost (well-formed, never-created) child IDs at counters far above anything created.
        uint64 neverCreatedWellFormedPolicy =
            (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(2_000_000);
        uint64[] memory tooManyNeverCreatedWellFormedPolicyList = new uint64[](MAX_CHILD_POLICIES + 1); // 5, all nonexistent
        for (uint256 i = 0; i < tooManyNeverCreatedWellFormedPolicyList.length; ++i) {
            tooManyNeverCreatedWellFormedPolicyList[i] =
                (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(1_000_000 + i);
        }

        // 1. ZERO-ADMIN: admin==0 AND type simple AND oversized child set → ZeroAddress fires first.
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        policyRegistry.createCompositePolicy(
            address(0), IPolicyRegistry.PolicyType.ALLOWLIST, tooManyNeverCreatedWellFormedPolicyList
        );

        // Fix: use a non-zero admin.

        // 2. INCOMPATIBLE-TYPE: valid admin, but simple type (ALLOWLIST) AND oversized child set
        //    → IncompatiblePolicyType fires before the count/size checks.
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.ALLOWLIST, tooManyNeverCreatedWellFormedPolicyList
        );

        // Fix: use a composite gate.

        // 3. COUNT-OUTSIDE-RANGE: composite type, but a child count outside [2, 4] (all nonexistent)
        //    → ChildPoliciesOutsideOfRange fires before the existence check. Exercises both the
        //    under-range (1 child) and over-range (> MAX_CHILD_POLICIES) ends.
        bytes memory outsideRange = abi.encodeWithSelector(
            IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
        );
        uint64[] memory one = new uint64[](1);
        one[0] = neverCreatedWellFormedPolicy;
        vm.expectRevert(outsideRange);
        policyRegistry.createCompositePolicy(admin, composite, one);

        vm.expectRevert(outsideRange);
        policyRegistry.createCompositePolicy(admin, composite, tooManyNeverCreatedWellFormedPolicyList);

        // Fix: bring the child count within [2, 4].

        // 4. CHILD-NOT-FOUND: in-range child set, but one child never existed → PolicyNotFound
        //    fires before the simple-vs-composite check.
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.createCompositePolicy(
            admin,
            composite,
            _childIds(tooManyNeverCreatedWellFormedPolicyList[0], tooManyNeverCreatedWellFormedPolicyList[1])
        );

        // Fix: replace the ghost with an existing simple policy.

        // 5. INVALID-CHILD: all children exist, but one is itself a composite → InvalidChildPolicy.
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, compositeChild));
        policyRegistry.createCompositePolicy(admin, composite, _childIds(validSimpleA, compositeChild));

        // Fix: replace the composite child with a simple policy.

        // Success.
        policyRegistry.createCompositePolicy(admin, composite, _childIds(validSimpleA, validSimpleB));
    }
}
