// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryCompositePolicyChildIdsTest is PolicyRegistryTest {
    /// @notice Verifies compositePolicyChildIds returns the set supplied at creation, in order
    /// @dev The registry preserves caller ordering verbatim; it neither sorts nor de-duplicates.
    function test_compositePolicyChildIds_success_returnsCreationSet() public {
        uint64[] memory children = _makeSimpleChildren(3);
        uint64 policyId = _createComposite(admin, admin, IPolicyRegistry.PolicyType.UNION, children);

        uint64[] memory got = policyRegistry.compositePolicyChildIds(policyId);
        assertEq(got.length, 3);
        for (uint256 i = 0; i < children.length; ++i) {
            assertEq(got[i], children[i]);
        }
    }

    /// @notice Verifies the getter tracks updateComposite as a full replacement
    /// @dev Replacing [a,b,c,d] with [c,d] must drop a and b entirely
    function test_compositePolicyChildIds_success_tracksUpdateComposite() public {
        uint64[] memory initial = _makeSimpleChildren(4);
        uint64 policyId = _createComposite(admin, admin, IPolicyRegistry.PolicyType.INTERSECT, initial);
        assertEq(policyRegistry.compositePolicyChildIds(policyId).length, 4);

        uint64[] memory replacement = _childIds(initial[2], initial[3]);
        vm.prank(admin);
        policyRegistry.updateComposite(policyId, replacement);

        uint64[] memory got = policyRegistry.compositePolicyChildIds(policyId);
        assertEq(got.length, 2);
        assertEq(got[0], initial[2]);
        assertEq(got[1], initial[3]);
    }

    /// @notice Verifies compositePolicyChildIds returns empty for a well-formed but uncreated id
    /// @dev Lookup should return for an uncreated ID.
    function test_compositePolicyChildIds_success_emptyForUncreated(uint64 seed) public view {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        assertEq(policyRegistry.compositePolicyChildIds(policyId).length, 0);
    }

    /// @notice Verifies a composite creation that fails persists no child set..
    function test_compositePolicyChildIds_success_emptyAfterFailedCreation() public {
        // Children first — `_makeSimpleChildren` consumes counter values of its own, so the
        // prediction below has to come after them.
        uint64[] memory children = _makeSimpleChildren(2);
        uint64 predicted = _predictNextPolicyId(IPolicyRegistry.PolicyType.UNION);

        // One child is below MIN_CHILD_POLICIES, so creation fails.
        uint64[] memory tooFew = new uint64[](1);
        tooFew[0] = children[0];
        vm.expectRevert();
        policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, tooFew);

        assertEq(policyRegistry.compositePolicyChildIds(predicted).length, 0);

        // Pins that `predicted` really is the ID the failed call would have taken, rather than
        // some unrelated unassigned ID that reads empty for free: the failure consumed no
        // counter, so the next valid creation claims exactly it.
        uint64 actual = _createComposite(admin, admin, IPolicyRegistry.PolicyType.UNION, children);
        assertEq(actual, predicted);
        assertEq(policyRegistry.compositePolicyChildIds(actual).length, 2);
    }

    /// @notice Verifies compositePolicyChildIds returns empty for a malformed id
    /// @dev Malformed-ID short-circuit returns empty.
    function test_compositePolicyChildIds_success_emptyForMalformedId(uint64 seed) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertEq(policyRegistry.compositePolicyChildIds(policyId).length, 0);
    }
}
