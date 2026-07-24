// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryCreateCompositePolicyTest is PolicyRegistryTest {
    // ============================================================
    //                           REVERTS
    // ============================================================

    /// @notice Verifies createCompositePolicy reverts when admin is the zero address
    /// @dev Required-field guard; checks ZeroAddress() error. Takes precedence over every later check.
    function test_createCompositePolicy_revert_zeroAdmin(address caller, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        uint64[] memory children = _makeSimpleChildren(2);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(address(0), pt, children);
    }

    /// @notice Verifies createCompositePolicy reverts when policyType is a simple gate
    /// @dev Type guard: composites must be UNION or INTERSECT; a simple ALLOWLIST/BLOCKLIST
    ///      type reverts with IncompatiblePolicyType().
    function test_createCompositePolicy_revert_incompatiblePolicyType(address caller, address admin_, uint8 typeIdx)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx); // ALLOWLIST or BLOCKLIST
        uint64[] memory children = _makeSimpleChildren(2);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }

    /// @notice Verifies createCompositePolicy reverts when the child count is outside [2, 4]
    /// @dev A composite must reference between MIN_CHILD_POLICIES (2) and MAX_CHILD_POLICIES (4)
    ///      simple policies, inclusive; checks ChildPoliciesOutsideOfRange(2, 4). Exercises both
    ///      under-range (0 and 1 children) and over-range (5..8 children) cases. The composite
    ///      child-policy range is distinct from the 64-account membership limit.
    function test_createCompositePolicy_revert_childPoliciesOutsideOfRange(
        address caller,
        address admin_,
        uint8 typeIdx,
        uint8 overflow
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        bytes memory expectedRevert = abi.encodeWithSelector(
            IPolicyRegistry.ChildPoliciesOutsideOfRange.selector, MIN_CHILD_POLICIES, MAX_CHILD_POLICIES
        );

        // Under range: 0 children.
        uint64[] memory none = new uint64[](0);
        vm.expectRevert(expectedRevert);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, none);

        // Under range: 1 child (a real, existing simple policy) — still below the minimum.
        uint64[] memory one = _makeSimpleChildren(1);
        vm.expectRevert(expectedRevert);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, one);

        // Over range: 5..8 valid simple children — only the count condition is broken.
        uint256 n = MAX_CHILD_POLICIES + 1 + (uint256(overflow) % 4); // 5..8
        uint64[] memory tooMany = _makeSimpleChildren(n);
        vm.expectRevert(expectedRevert);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, tooMany);
    }

    /// @notice Verifies createCompositePolicy reverts when a child policy does not exist
    /// @dev Checks PolicyNotFound(). Both children are well-formed but never-created IDs, so the
    ///      existence check fails before the simple-vs-composite check.
    function test_createCompositePolicy_revert_policyNotFound(
        address caller,
        address admin_,
        uint8 typeIdx,
        uint64 seed
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        uint64[] memory children = new uint64[](2);
        children[0] = _wellFormedUncreatedPolicyId(seed);
        children[1] = _wellFormedUncreatedPolicyId(seed ^ 0xdead);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }

    /// @notice Verifies createCompositePolicy reverts when a child is itself a composite
    /// @dev Child policies must be simple; a composite child reverts with
    ///      InvalidChildPolicy(childPolicyId) carrying the offending ID.
    function test_createCompositePolicy_revert_invalidChildPolicy(address caller, address admin_, uint8 typeIdx)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);

        // A composite policy to use as an (invalid) child.
        uint64 compositeChild = _createComposite(IPolicyRegistry.PolicyType.UNION, 2);
        // A valid simple sibling so the child set has the required size and the composite child
        // is the sole offending entry.
        uint64 simpleChild = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);

        uint64[] memory children = _childIds(simpleChild, compositeChild);
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, compositeChild));
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }

    /// @notice Verifies createCompositePolicy reverts when a child is a built-in sentinel
    /// @dev Built-in sentinels (ALWAYS_ALLOW_ID / ALWAYS_BLOCK_ID) are reserved and may not be
    ///      composed; each reverts with InvalidChildPolicy(childPolicyId) carrying the offending ID.
    function test_createCompositePolicy_revert_builtinChild(address caller, address admin_, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);

        // A valid simple sibling; creating it also lazily initializes the built-in sentinels so
        // they pass the existence check and the built-in guard is the sole offending entry.
        uint64 simpleChild = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);

        // ALWAYS_ALLOW_ID as a child.
        uint64[] memory withAllow = _childIds(simpleChild, PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        vm.expectRevert(
            abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, PolicyRegistryConstants.ALWAYS_ALLOW_ID)
        );
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, withAllow);

        // ALWAYS_BLOCK_ID as a child.
        uint64[] memory withBlock = _childIds(simpleChild, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        vm.expectRevert(
            abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, PolicyRegistryConstants.ALWAYS_BLOCK_ID)
        );
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, withBlock);
    }

    /// @notice Verifies createCompositePolicy panics with arithmetic overflow at the counter max
    /// @dev Slot-writes nextCounter to type(uint56).max after seeding children to avoid iterating
    ///      2^56 times. Mock-only: vm.store cannot write to native precompile addresses.
    ///      Matches the Rust precompile which reverts with Panic(UnderOverflow) = Panic(0x11).
    function test_createCompositePolicy_revert_counterOverflow(address caller, address admin_, uint8 typeIdx) public {
        vm.skip(livePrecompiles);
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);

        // Seed valid children first (advances the counter past the built-ins), then force overflow.
        uint64[] memory children = _makeSimpleChildren(2);
        vm.store(
            address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot(), bytes32(uint256(type(uint56).max))
        );

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }

    // ============================================================
    //                           SUCCESS
    // ============================================================

    /// @notice Verifies createCompositePolicy assigns a fresh UNION policy id
    /// @dev Paired slot: admin lane matches, exists bit set, ID top byte = UNION.
    function test_createCompositePolicy_success_union(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        uint64[] memory children = _makeSimpleChildren(2);

        uint64 predicted = _predictNextPolicyId(IPolicyRegistry.PolicyType.UNION);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createCompositePolicy(admin_, IPolicyRegistry.PolicyType.UNION, children);
        assertEq(policyId, predicted);
        assertTrue(policyRegistry.policyExists(policyId));
        assertEq(policyRegistry.policyAdmin(policyId), admin_);

        uint256 packed = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)));
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(packed),
            admin_,
            "policies[id] slot admin must reflect the composite admin"
        );
        assertTrue(MockPolicyRegistryStorage.policyExistsFromPacked(packed), "policies[id] slot exists bit must be set");
        assertEq(
            MockPolicyRegistryStorage.policyTypeFromId(policyId),
            uint8(IPolicyRegistry.PolicyType.UNION),
            "policy ID high byte must encode UNION"
        );
    }

    /// @notice Verifies createCompositePolicy assigns a fresh INTERSECT policy id
    /// @dev Paired slot: admin lane matches, exists bit set, ID top byte = INTERSECT.
    function test_createCompositePolicy_success_intersect(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        uint64[] memory children = _makeSimpleChildren(2);

        uint64 predicted = _predictNextPolicyId(IPolicyRegistry.PolicyType.INTERSECT);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createCompositePolicy(admin_, IPolicyRegistry.PolicyType.INTERSECT, children);
        assertEq(policyId, predicted);
        assertTrue(policyRegistry.policyExists(policyId));
        assertEq(policyRegistry.policyAdmin(policyId), admin_);

        uint256 packed = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)));
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(packed),
            admin_,
            "policies[id] slot admin must reflect the composite admin"
        );
        assertTrue(MockPolicyRegistryStorage.policyExistsFromPacked(packed), "policies[id] slot exists bit must be set");
        assertEq(
            MockPolicyRegistryStorage.policyTypeFromId(policyId),
            uint8(IPolicyRegistry.PolicyType.INTERSECT),
            "policy ID high byte must encode INTERSECT"
        );
    }

    /// @notice Verifies createCompositePolicy accepts a child set exactly at the cap
    /// @dev Boundary check: MAX_CHILD_POLICIES (4) children is inclusive.
    function test_createCompositePolicy_success_atMaxChildren(address caller, address admin_, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        uint64[] memory children = _makeSimpleChildren(MAX_CHILD_POLICIES);
        vm.prank(caller);
        uint64 policyId = policyRegistry.createCompositePolicy(admin_, pt, children);
        assertTrue(policyRegistry.policyExists(policyId));
    }

    /// @notice Verifies sequential composite creates each consume a fresh id from the global counter
    /// @dev Each create's ID matches the prediction taken from the live counter immediately before it.
    function test_createCompositePolicy_success_advancesNextPolicyId(address admin_, uint8 typeIdxA, uint8 typeIdxB)
        public
    {
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType ptA = _creatableCompositeType(typeIdxA);
        IPolicyRegistry.PolicyType ptB = _creatableCompositeType(typeIdxB);

        uint64[] memory childrenA = _makeSimpleChildren(2);
        uint64 predictedA = _predictNextPolicyId(ptA);
        uint64 idA = policyRegistry.createCompositePolicy(admin_, ptA, childrenA);
        assertEq(idA, predictedA);

        uint64[] memory childrenB = _makeSimpleChildren(2);
        uint64 predictedB = _predictNextPolicyId(ptB);
        uint64 idB = policyRegistry.createCompositePolicy(admin_, ptB, childrenB);
        assertEq(idB, predictedB);

        assertTrue(idA != idB);
    }

    /// @notice Verifies createCompositePolicy emits PolicyCreated with the correct args
    function test_createCompositePolicy_success_emitsPolicyCreated(address caller, address admin_, uint8 typeIdx)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        uint64[] memory children = _makeSimpleChildren(2);

        uint64 expectedId = _predictNextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyCreated(expectedId, caller, pt);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }

    /// @notice Verifies createCompositePolicy emits PolicyAdminUpdated(previousAdmin = 0) on initial assignment
    function test_createCompositePolicy_success_emitsInitialPolicyAdminUpdated(
        address caller,
        address admin_,
        uint8 typeIdx
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        uint64[] memory children = _makeSimpleChildren(2);

        uint64 expectedId = _predictNextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(expectedId, address(0), admin_);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }

    /// @notice Verifies createCompositePolicy emits CompositePolicyUpdated carrying the full child set
    /// @dev The event is emitted on creation as well as on every subsequent update; the payload is the
    ///      complete post-create child set.
    function test_createCompositePolicy_success_emitsCompositePolicyUpdated(
        address caller,
        address admin_,
        uint8 typeIdx
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatableCompositeType(typeIdx);
        uint64[] memory children = _makeSimpleChildren(2);

        uint64 expectedId = _predictNextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.CompositePolicyUpdated(expectedId, caller, children);
        vm.prank(caller);
        policyRegistry.createCompositePolicy(admin_, pt, children);
    }
}
