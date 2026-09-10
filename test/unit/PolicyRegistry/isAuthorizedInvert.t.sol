// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @notice Covers the invert (NOT) flag on the policy ID. IsAuthrized evaluates the base policy and inverts the result.
contract PolicyRegistryIsAuthorizedInvertTest is PolicyRegistryTest {
    uint64 internal constant INVERTED_POLICY_BIT = PolicyRegistryConstants.INVERTED_POLICY_BIT;

    function _addAllowlistMember(uint64 policyId, address account) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateAllowlist(policyId, true, accounts);
    }

    function _addBlocklistMember(uint64 policyId, address account) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateBlocklist(policyId, true, accounts);
    }

    // ============================================================
    //             FAIL-CLOSED INVARIANT (the point of 2a)
    // ============================================================

    /// @notice Inverting an uncreated (unknown) base denies rather than allowing everyone.
    function test_isAuthorized_success_invertUnknownAllowlistBaseDenies(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 base = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(counter);
        assertFalse(policyRegistry.isAuthorized(base | INVERTED_POLICY_BIT, account));
    }

    /// @notice Inverting an uncreated BLOCKLIST base also denies (fail-closed)
    function test_isAuthorized_success_invertUnknownBlocklistBaseDenies(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 base = (uint64(uint8(IPolicyRegistry.PolicyType.BLOCKLIST)) << 56) | uint64(counter);
        // Sanity: the plain unknown blocklist authorizes (empty-member-set semantics)...
        assertTrue(policyRegistry.isAuthorized(base, account));
        // ...but its inverse must NOT become allow-everyone; the base does not exist.
        assertFalse(policyRegistry.isAuthorized(base | INVERTED_POLICY_BIT, account));
    }

    /// @notice Inverting a malformed base denies.
    function test_isAuthorized_success_invertMalformedBaseDenies(uint64 seed, address account) public view {
        uint64 base = _malformedPolicyId(seed) & ~INVERTED_POLICY_BIT;
        assertFalse(policyRegistry.isAuthorized(base | INVERTED_POLICY_BIT, account));
    }

    // ============================================================
    //                    SIMPLE-POLICY INVERSION
    // ============================================================

    /// @notice NOT(allowlist): a member of the base is denied by the inverse.
    function test_isAuthorized_success_invertAllowlistMemberDenied(address account) public {
        uint64 base = _createAllowlist();
        _addAllowlistMember(base, account);
        assertTrue(policyRegistry.isAuthorized(base, account));
        assertFalse(policyRegistry.isAuthorized(base | INVERTED_POLICY_BIT, account));
    }

    /// @notice NOT(allowlist): a non-member of the base is authorized by the inverse.
    function test_isAuthorized_success_invertAllowlistNonMemberAuthorized(address account) public {
        uint64 base = _createAllowlist();
        assertFalse(policyRegistry.isAuthorized(base, account));
        assertTrue(policyRegistry.isAuthorized(base | INVERTED_POLICY_BIT, account));
    }

    /// @notice NOT(blocklist): a blocked account (base denies) is authorized by the inverse.
    function test_isAuthorized_success_invertBlocklistMemberAuthorized(address account) public {
        uint64 base = _createBlocklist();
        _addBlocklistMember(base, account);
        assertFalse(policyRegistry.isAuthorized(base, account));
        assertTrue(policyRegistry.isAuthorized(base | INVERTED_POLICY_BIT, account));
    }

    // ============================================================
    //                     BUILT-IN INVERSION
    // ============================================================

    /// @notice NOT(ALWAYS_ALLOW) denies every account.
    function test_isAuthorized_success_invertAlwaysAllowDenies(address account) public {
        // Touch the registry so the built-ins are initialized before the query.
        _createAllowlist();
        assertFalse(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_ALLOW_ID | INVERTED_POLICY_BIT, account));
    }

    /// @notice NOT(ALWAYS_BLOCK) authorizes every account.
    function test_isAuthorized_success_invertAlwaysBlockAuthorizes(address account) public {
        _createAllowlist();
        assertTrue(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_BLOCK_ID | INVERTED_POLICY_BIT, account));
    }

    // ============================================================
    //         COMPOSITE WITH PER-CHILD INVERT: "A AND NOT X"
    // ============================================================

    /// @notice INTERSECT[A, ~X] reads as "on A and not on X". A member of both A and X is
    ///         denied (fails the NOT-X leg); a member of A only is authorized.
    function test_isAuthorized_success_intersectAllowAndNotX(address account) public {
        uint64 a = _createAllowlist();
        uint64 x = _createAllowlist();
        _addAllowlistMember(a, account);
        uint64 invertedX = x | INVERTED_POLICY_BIT;
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, invertedX)
        );

        // account is on A and NOT on X -> authorized.
        assertTrue(policyRegistry.isAuthorized(composite, account));

        // Add account to X: now it is on A but IS on X -> the ~X leg denies.
        _addAllowlistMember(x, account);
        assertFalse(policyRegistry.isAuthorized(composite, account));
    }

    // ============================================================
    //           COMPOSITE-CHILD VALIDATION WITH INVERT FLAG
    // ============================================================

    /// @notice An inverted simple child is accepted and stored verbatim (flag intact).
    function test_createCompositePolicy_success_invertedSimpleChild() public {
        uint64 a = _createAllowlist();
        uint64 x = _createAllowlist();
        uint64 invertedX = x | INVERTED_POLICY_BIT;
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, invertedX)
        );
        uint64[] memory children = policyRegistry.compositePolicyChildIds(composite);
        assertEq(children[1], invertedX);
    }

    /// @notice An inverted child whose base does not exist reverts with PolicyNotFound —
    ///         the invert flag cannot smuggle a non-existent child past validation.
    function test_createCompositePolicy_revert_invertedChildBaseNotFound() public {
        uint64 a = _createAllowlist();
        uint64 missing = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(9999);
        uint64 invertedMissing = missing | INVERTED_POLICY_BIT;
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, invertedMissing)
        );
    }

    /// @notice An inverted COMPOSITE child is rejected: the invert flag must not let a
    ///         nested gate slip past the flat-tree invariant.
    function test_createCompositePolicy_revert_invertedCompositeChild() public {
        uint64 a = _createAllowlist();
        uint64 b = _createAllowlist();
        uint64 inner = policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(a, b));
        uint64 invertedInner = inner | INVERTED_POLICY_BIT;
        uint64 c = _createAllowlist();
        vm.expectRevert(
            abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, invertedInner)
        );
        policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(c, invertedInner)
        );
    }

    // ============================================================
    //        compositePolicyChildIds RETURNS CHILDREN VERBATIM
    // ============================================================

    /// @notice The read returns child IDs exactly as stored: a plain child is returned plain,
    ///         an inverted child is returned with its invert flag intact.
    function test_compositePolicyChildIds_success_returnsChildrenVerbatim() public {
        uint64 a = _createAllowlist();
        uint64 x = _createAllowlist();
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x | INVERTED_POLICY_BIT)
        );
        uint64[] memory children = policyRegistry.compositePolicyChildIds(composite);
        assertEq(children[0], a, "plain child returned unchanged");
        assertEq(children[1], x | INVERTED_POLICY_BIT, "inverted child returned with flag set");
    }

    /// @notice Querying the composite's own inverse returns the identical child set
    function test_compositePolicyChildIds_success_invertedCompositeIdReturnsSameSet() public {
        uint64 a = _createAllowlist();
        uint64 x = _createAllowlist();
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x | INVERTED_POLICY_BIT)
        );
        uint64[] memory viaBase = policyRegistry.compositePolicyChildIds(composite);
        uint64[] memory viaInverse = policyRegistry.compositePolicyChildIds(composite | INVERTED_POLICY_BIT);
        assertEq(viaInverse.length, viaBase.length);
        for (uint256 i = 0; i < viaBase.length; ++i) {
            assertEq(viaInverse[i], viaBase[i]);
        }
    }

    /// @notice updateComposite preserves the verbatim-return contract: after replacing the
    ///         child set, an inverted child still reads back with its flag set.
    function test_compositePolicyChildIds_success_returnsInvertedChildVerbatimAfterUpdate() public {
        uint64 a = _createAllowlist();
        uint64 x = _createAllowlist();
        uint64 y = _createAllowlist();
        uint64 composite =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x));

        vm.prank(admin);
        policyRegistry.updateComposite(composite, _childIds(a, y | INVERTED_POLICY_BIT));

        uint64[] memory children = policyRegistry.compositePolicyChildIds(composite);
        assertEq(children[0], a);
        assertEq(children[1], y | INVERTED_POLICY_BIT, "inverted child persists verbatim after update");
    }

    // ============================================================
    //                  GETTER STRIP SEMANTICS
    // ============================================================

    /// @notice policyExists(~id) mirrors policyExists(id): the inverse of a created policy
    ///         reports existing
    function test_policyExists_success_invertMirrorsBase(uint56 counter) public {
        vm.assume(counter > 1);
        uint64 created = _createAllowlist();
        assertTrue(policyRegistry.policyExists(created | INVERTED_POLICY_BIT));

        uint64 unknown = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(counter);
        assertEq(policyRegistry.policyExists(unknown | INVERTED_POLICY_BIT), policyRegistry.policyExists(unknown));
    }

    /// @notice policyAdmin(~id) resolves to the base's admin.
    function test_policyAdmin_success_invertResolvesBaseAdmin(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));
        uint64 base = _createAllowlist(admin, policyAdmin);
        assertEq(policyRegistry.policyAdmin(base | INVERTED_POLICY_BIT), policyAdmin);
    }

    // ============================================================
    //                 invertedPolicyId() VIEW
    // ============================================================

    /// @notice The registry view toggles the invert flag, is involutive, and never reverts —
    ///         including for unknown/malformed IDs (it reads no state).
    function test_invertedPolicyId_success_togglesAndRoundTrips(uint64 base) public view {
        uint64 inverted = policyRegistry.invertedPolicyId(base);
        assertEq(inverted, base ^ INVERTED_POLICY_BIT);
        assertEq(policyRegistry.invertedPolicyId(inverted), base);
    }

    /// @notice End-to-end: authorizing against the view's result negates the base decision.
    function test_invertedPolicyId_success_negatesAuthorization(address account) public {
        uint64 base = _createAllowlist();
        _addAllowlistMember(base, account);
        uint64 inverted = policyRegistry.invertedPolicyId(base);
        assertTrue(policyRegistry.isAuthorized(base, account));
        assertFalse(policyRegistry.isAuthorized(inverted, account));
    }
}
