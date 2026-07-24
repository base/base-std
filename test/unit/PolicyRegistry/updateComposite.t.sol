// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract PolicyRegistryUpdateCompositeTest is PolicyRegistryTest {
    // ============================================================
    //                           REVERTS
    // ============================================================

    /// @notice Verifies updateComposite reverts for an unknown composite id
    /// @dev The target policy must exist; checks PolicyNotFound(). Fires before any child validation.
    function test_updateComposite_revert_policyNotFound(address caller, uint64 seed) public {
        _assumeValidCaller(caller);
        uint64 ghostComposite = _wellFormedUncreatedPolicyId(seed);
        uint64[] memory children =
            _childIds(_wellFormedUncreatedPolicyId(seed ^ 1), _wellFormedUncreatedPolicyId(seed ^ 2));
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.updateComposite(ghostComposite, children);
    }

    /// @notice Verifies updateComposite reverts when the target is a simple policy
    /// @dev Type guard: updateComposite only operates on UNION/INTERSECT policies; a simple
    ///      ALLOWLIST/BLOCKLIST target reverts with IncompatiblePolicyType().
    function test_updateComposite_revert_incompatiblePolicyType(uint8 typeIdx) public {
        IPolicyRegistry.PolicyType simple = _creatablePolicyType(typeIdx);
        uint64 simpleId = policyRegistry.createPolicy(admin, simple);
        uint64[] memory children = _makeSimpleChildren(2);
        // Call as the policy admin so the type guard, not the auth guard, is under test.
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        vm.prank(admin);
        policyRegistry.updateComposite(simpleId, children);
    }

    /// @notice Verifies updateComposite reverts when called by a non-admin
    /// @dev Access control: only the current admin may replace the child set; checks Unauthorized().
    function test_updateComposite_revert_unauthorized(address caller, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        uint64[] memory children = _makeSimpleChildren(2);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.updateComposite(composite, children);
    }

    /// @notice Verifies a renounced composite can never be updated
    /// @dev After renounceAdmin the admin lane is zero, so every updateComposite reverts with
    ///      Unauthorized() — the policy is frozen but still observable.
    function test_updateComposite_revert_renouncedComposite(uint8 typeIdx) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        vm.prank(admin);
        policyRegistry.renounceAdmin(composite);

        uint64[] memory children = _makeSimpleChildren(2);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(admin); // former admin — no longer authorized
        policyRegistry.updateComposite(composite, children);
    }

    /// @notice Verifies updateComposite reverts when the new child count is outside [2, 4]
    /// @dev A composite must reference between MIN_CHILD_POLICIES (2) and MAX_CHILD_POLICIES (4)
    ///      simple policies, inclusive; checks ChildPoliciesOutsideOfRange(2, 4). There is no
    ///      clear-the-list path. Exercises both under-range (0 and 1 children) and over-range
    ///      (5..8 children) cases.
    function test_updateComposite_revert_childPoliciesOutsideOfRange(uint8 typeIdx, uint8 overflow) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        bytes memory expectedRevert = abi.encodeWithSelector(
            IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
        );

        // Under range: 0 children.
        uint64[] memory none = new uint64[](0);
        vm.expectRevert(expectedRevert);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, none);

        // Under range: 1 child.
        uint64[] memory one = _makeSimpleChildren(1);
        vm.expectRevert(expectedRevert);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, one);

        // Over range: 5..8 valid simple children.
        uint256 n = MAX_CHILD_POLICIES + 1 + (uint256(overflow) % 4); // 5..8
        uint64[] memory tooMany = _makeSimpleChildren(n);
        vm.expectRevert(expectedRevert);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, tooMany);
    }

    /// @notice Verifies updateComposite reverts when a new child policy does not exist
    /// @dev Checks PolicyNotFound() for a well-formed but never-created child.
    function test_updateComposite_revert_policyNotFoundChild(uint8 typeIdx, uint64 seed) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        uint64[] memory children =
            _childIds(_wellFormedUncreatedPolicyId(seed), _wellFormedUncreatedPolicyId(seed ^ 0xbeef));
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, children);
    }

    /// @notice Verifies updateComposite reverts when a new child is itself a composite
    /// @dev Child policies must be simple; a composite child reverts with
    ///      InvalidChildPolicy(childPolicyId) carrying the offending ID.
    function test_updateComposite_revert_invalidChildPolicy(uint8 typeIdx) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        uint64 otherComposite = _createComposite(IPolicyRegistry.PolicyType.INTERSECT, 2);
        uint64 simpleChild = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);

        uint64[] memory children = _childIds(simpleChild, otherComposite);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, otherComposite));
        vm.prank(admin);
        policyRegistry.updateComposite(composite, children);
    }

    /// @notice Verifies updateComposite reverts when a new child is a built-in sentinel
    /// @dev Built-in sentinels (ALWAYS_ALLOW_ID / ALWAYS_BLOCK_ID) are reserved and may not be
    ///      composed; each reverts with InvalidChildPolicy(childPolicyId) carrying the offending ID.
    function test_updateComposite_revert_builtinChild(uint8 typeIdx) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        uint64 simpleChild = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);

        uint64[] memory withAllow = _childIds(simpleChild, PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        vm.expectRevert(
            abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, PolicyRegistryConstants.ALWAYS_ALLOW_ID)
        );
        vm.prank(admin);
        policyRegistry.updateComposite(composite, withAllow);

        uint64[] memory withBlock = _childIds(simpleChild, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        vm.expectRevert(
            abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, PolicyRegistryConstants.ALWAYS_BLOCK_ID)
        );
        vm.prank(admin);
        policyRegistry.updateComposite(composite, withBlock);
    }

    // ============================================================
    //                     EVENT + REPLACEMENT
    // ============================================================

    /// @notice Verifies updateComposite emits CompositePolicyUpdated with the full new child set
    /// @dev One event per call carrying the complete post-update set; topic args match policyId / updater.
    function test_updateComposite_success_emitsCompositePolicyUpdated(uint8 typeIdx) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        uint64[] memory newChildren = _makeSimpleChildren(2);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.CompositePolicyUpdated(composite, admin, newChildren);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, newChildren);
    }

    /// @notice Verifies updateComposite accepts a new child set exactly at the cap
    /// @dev Boundary check: MAX_CHILD_POLICIES (4) children is inclusive.
    function test_updateComposite_success_atMaxChildren(uint8 typeIdx) public {
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        uint64[] memory newChildren = _makeSimpleChildren(MAX_CHILD_POLICIES);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, newChildren);
        assertTrue(policyRegistry.policyExists(composite));
    }

    /// @notice Verifies updateComposite replaces the child set in full rather than merging
    /// @dev Behavioral proof via isAuthorized: an account authorized under the OLD child set is no
    ///      longer authorized once the set is swapped for children it does not belong to.
    function test_updateComposite_success_replacesChildSet(address account) public {
        // UNION over two allowlists; `account` is a member of the first only.
        uint64 childA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 composite =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(childA, childB));

        address[] memory one = new address[](1);
        one[0] = account;
        vm.prank(admin);
        policyRegistry.updateAllowlist(childA, true, one);
        assertTrue(policyRegistry.isAuthorized(composite, account), "union should authorize a member of child A");

        // Swap in a fresh child set that `account` does not belong to.
        uint64 childC = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childD = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.updateComposite(composite, _childIds(childC, childD));

        assertFalse(
            policyRegistry.isAuthorized(composite, account),
            "old child set must no longer govern after full replacement"
        );
    }
}
