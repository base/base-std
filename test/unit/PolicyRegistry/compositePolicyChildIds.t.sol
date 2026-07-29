// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

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
    /// @dev Replacing [a,b] with [c,d] must drop a and b entirely, with no stale tail.
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

    /// @notice Verifies the getter agrees with the CompositePolicyUpdated event payload
    /// @dev Indexers reconcile logs against live reads; the two must never disagree.
    function test_compositePolicyChildIds_success_matchesEmittedEvent() public {
        uint64[] memory children = _makeSimpleChildren(2);

        vm.recordLogs();
        uint64 policyId = _createComposite(admin, admin, IPolicyRegistry.PolicyType.UNION, children);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 index = _firstLogIndex(logs, IPolicyRegistry.CompositePolicyUpdated.selector);
        assertGe(index, 0, "CompositePolicyUpdated not emitted");
        // `policyId` and `updater` are indexed, so only the child array sits in `data`.
        uint64[] memory emitted = abi.decode(logs[uint256(index)].data, (uint64[]));

        uint64[] memory got = policyRegistry.compositePolicyChildIds(policyId);
        assertEq(got.length, emitted.length);
        for (uint256 i = 0; i < got.length; ++i) {
            assertEq(got[i], emitted[i]);
        }
    }

    /// @notice Verifies a duplicated child ID is returned as many times as supplied
    /// @dev Documents that the registry does not de-duplicate; a UNION over [a,a] is legal.
    function test_compositePolicyChildIds_success_preservesDuplicates() public {
        uint64 child = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 policyId = _createComposite(admin, admin, IPolicyRegistry.PolicyType.UNION, _childIds(child, child));

        uint64[] memory got = policyRegistry.compositePolicyChildIds(policyId);
        assertEq(got.length, 2);
        assertEq(got[0], child);
        assertEq(got[1], child);
    }

    /// @notice Verifies the child set survives an admin transfer and a renounce
    /// @dev The set lives in its own slot, untouched by admin-lane writes to the packed word.
    function test_compositePolicyChildIds_success_survivesRenounce() public {
        uint64[] memory children = _makeSimpleChildren(2);
        uint64 policyId = _createComposite(admin, admin, IPolicyRegistry.PolicyType.UNION, children);

        vm.prank(admin);
        policyRegistry.renounceAdmin(policyId);

        // Frozen forever (updateComposite now reverts Unauthorized for every caller), but still readable.
        uint64[] memory got = policyRegistry.compositePolicyChildIds(policyId);
        assertEq(got.length, 2);
        assertEq(got[0], children[0]);
        assertEq(got[1], children[1]);
    }

    /// @notice Verifies compositePolicyChildIds returns empty for a simple policy
    /// @dev Simple policies never have a child set; the gate byte short-circuits before any read.
    function test_compositePolicyChildIds_success_emptyForSimplePolicy() public {
        uint64 allowlist = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 blocklist = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        assertEq(policyRegistry.compositePolicyChildIds(allowlist).length, 0);
        assertEq(policyRegistry.compositePolicyChildIds(blocklist).length, 0);
    }

    /// @notice Verifies compositePolicyChildIds returns empty for built-in sentinels
    function test_compositePolicyChildIds_success_emptyForBuiltins() public view {
        assertEq(policyRegistry.compositePolicyChildIds(PolicyRegistryConstants.ALWAYS_ALLOW_ID).length, 0);
        assertEq(policyRegistry.compositePolicyChildIds(PolicyRegistryConstants.ALWAYS_BLOCK_ID).length, 0);
    }

    /// @notice Verifies compositePolicyChildIds returns empty for a well-formed but uncreated id
    /// @dev Lookup miss returns an empty array rather than reverting.
    function test_compositePolicyChildIds_success_emptyForUncreated(uint64 seed) public view {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        assertEq(policyRegistry.compositePolicyChildIds(policyId).length, 0);
    }

    /// @notice Verifies compositePolicyChildIds returns empty for a malformed id
    /// @dev Malformed-ID short-circuit returns empty, matching the rest of the read surface.
    function test_compositePolicyChildIds_success_emptyForMalformedId(uint64 seed) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertEq(policyRegistry.compositePolicyChildIds(policyId).length, 0);
    }

    /// @notice Verifies an existing composite never reports fewer than MIN_CHILD_POLICIES children
    /// @dev This is what makes an empty return unambiguously mean "not a composite": there is no
    ///      clear-the-list path, so a created composite can never decay to an empty set.
    function test_compositePolicyChildIds_success_createdCompositeIsNeverEmpty() public {
        uint64 policyId = _createComposite(IPolicyRegistry.PolicyType.UNION, MIN_CHILD_POLICIES);

        uint64[] memory empty = new uint64[](0);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
            )
        );
        policyRegistry.updateComposite(policyId, empty);

        assertEq(policyRegistry.compositePolicyChildIds(policyId).length, MIN_CHILD_POLICIES);
    }
}
