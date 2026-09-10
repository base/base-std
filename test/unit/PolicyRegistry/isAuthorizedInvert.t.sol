// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @notice Covers the invert (NOT) flag on the policy ID: `isAuthorized` resolves the
///         base policy (`policyId & ~INVERT_BIT`) and returns the opposite of its
///         decision, so one membership set can be evaluated as include or exclude
///         without maintaining a mirror list.
///
/// @dev    The load-bearing property is FAIL-CLOSED: an inverted ID over an unknown or
///         malformed base must deny, never flip a would-be deny into allow-everyone on a
///         gated mint / transfer / seize path. Those cases lead the suite.
contract PolicyRegistryIsAuthorizedInvertTest is PolicyRegistryTest {
    /// @dev The shared invert flag (bit 63 of the ID); single source of truth.
    uint64 internal constant INVERT_BIT = B20Constants.POLICY_INVERT_BIT;

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
    /// @dev The whole reason the invert flag is gated on base existence. Without the gate
    ///      a garbage or typo'd ID with the bit set would authorize every account.
    function test_isAuthorized_success_invertUnknownAllowlistBaseDenies(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 base = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(counter);
        assertFalse(policyRegistry.isAuthorized(base | INVERT_BIT, account));
    }

    /// @notice Inverting an uncreated BLOCKLIST base also denies (fail-closed), even though
    ///         a plain unknown blocklist authorizes — existence is what gates the flip.
    function test_isAuthorized_success_invertUnknownBlocklistBaseDenies(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 base = (uint64(uint8(IPolicyRegistry.PolicyType.BLOCKLIST)) << 56) | uint64(counter);
        // Sanity: the plain unknown blocklist authorizes (empty-member-set semantics)...
        assertTrue(policyRegistry.isAuthorized(base, account));
        // ...but its inverse must NOT become allow-everyone; the base does not exist.
        assertFalse(policyRegistry.isAuthorized(base | INVERT_BIT, account));
    }

    /// @notice Inverting a malformed base (type byte above the enum, after stripping the
    ///         invert flag) denies.
    function test_isAuthorized_success_invertMalformedBaseDenies(uint64 seed, address account) public view {
        uint64 base = _malformedPolicyId(seed) & ~INVERT_BIT;
        assertFalse(policyRegistry.isAuthorized(base | INVERT_BIT, account));
    }

    // ============================================================
    //                    SIMPLE-POLICY INVERSION
    // ============================================================

    /// @notice NOT(allowlist): a member of the base is denied by the inverse.
    function test_isAuthorized_success_invertAllowlistMemberDenied(address account) public {
        uint64 base = _createAllowlist();
        _addAllowlistMember(base, account);
        assertTrue(policyRegistry.isAuthorized(base, account));
        assertFalse(policyRegistry.isAuthorized(base | INVERT_BIT, account));
    }

    /// @notice NOT(allowlist): a non-member of the base is authorized by the inverse.
    function test_isAuthorized_success_invertAllowlistNonMemberAuthorized(address account) public {
        uint64 base = _createAllowlist();
        assertFalse(policyRegistry.isAuthorized(base, account));
        assertTrue(policyRegistry.isAuthorized(base | INVERT_BIT, account));
    }

    /// @notice NOT(blocklist): a blocked account (base denies) is authorized by the inverse.
    function test_isAuthorized_success_invertBlocklistMemberAuthorized(address account) public {
        uint64 base = _createBlocklist();
        _addBlocklistMember(base, account);
        assertFalse(policyRegistry.isAuthorized(base, account));
        assertTrue(policyRegistry.isAuthorized(base | INVERT_BIT, account));
    }

    // ============================================================
    //                     BUILT-IN INVERSION
    // ============================================================

    /// @notice NOT(ALWAYS_ALLOW) denies every account.
    function test_isAuthorized_success_invertAlwaysAllowDenies(address account) public {
        // Touch the registry so the built-ins are initialized before the query.
        _createAllowlist();
        assertFalse(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_ALLOW_ID | INVERT_BIT, account));
    }

    /// @notice NOT(ALWAYS_BLOCK) authorizes every account.
    function test_isAuthorized_success_invertAlwaysBlockAuthorizes(address account) public {
        _createAllowlist();
        assertTrue(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_BLOCK_ID | INVERT_BIT, account));
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

        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x | INVERT_BIT)
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
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x | INVERT_BIT)
        );
        uint64[] memory children = policyRegistry.compositePolicyChildIds(composite);
        assertEq(children[1], x | INVERT_BIT);
    }

    /// @notice An inverted child whose base does not exist reverts with PolicyNotFound —
    ///         the invert flag cannot smuggle a non-existent child past validation.
    function test_createCompositePolicy_revert_invertedChildBaseNotFound() public {
        uint64 a = _createAllowlist();
        uint64 missing = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(9999);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, missing | INVERT_BIT)
        );
    }

    /// @notice An inverted COMPOSITE child is rejected: the invert flag must not let a
    ///         nested gate slip past the flat-tree invariant.
    function test_createCompositePolicy_revert_invertedCompositeChild() public {
        uint64 a = _createAllowlist();
        uint64 b = _createAllowlist();
        uint64 inner = policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(a, b));

        uint64 c = _createAllowlist();
        vm.expectRevert(abi.encodeWithSelector(IPolicyRegistry.InvalidChildPolicy.selector, inner | INVERT_BIT));
        policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(c, inner | INVERT_BIT)
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
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x | INVERT_BIT)
        );
        uint64[] memory children = policyRegistry.compositePolicyChildIds(composite);
        assertEq(children[0], a, "plain child returned unchanged");
        assertEq(children[1], x | INVERT_BIT, "inverted child returned with flag set");
    }

    /// @notice Querying the composite's own inverse returns the identical child set (only the
    ///         queried ID's flag is stripped; the children are untouched).
    function test_compositePolicyChildIds_success_invertedCompositeIdReturnsSameSet() public {
        uint64 a = _createAllowlist();
        uint64 x = _createAllowlist();
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(a, x | INVERT_BIT)
        );
        uint64[] memory viaBase = policyRegistry.compositePolicyChildIds(composite);
        uint64[] memory viaInverse = policyRegistry.compositePolicyChildIds(composite | INVERT_BIT);
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
        policyRegistry.updateComposite(composite, _childIds(a, y | INVERT_BIT));

        uint64[] memory children = policyRegistry.compositePolicyChildIds(composite);
        assertEq(children[0], a);
        assertEq(children[1], y | INVERT_BIT, "inverted child persists verbatim after update");
    }

    // ============================================================
    //                  GETTER STRIP SEMANTICS
    // ============================================================

    /// @notice policyExists(~id) mirrors policyExists(id): the inverse of a created policy
    ///         reports existing (so a token can store and re-validate ~id), and the inverse
    ///         of an unknown base reports non-existent.
    function test_policyExists_success_invertMirrorsBase(uint56 counter) public {
        vm.assume(counter > 1);
        uint64 created = _createAllowlist();
        assertTrue(policyRegistry.policyExists(created | INVERT_BIT));

        uint64 unknown = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(counter);
        assertEq(policyRegistry.policyExists(unknown | INVERT_BIT), policyRegistry.policyExists(unknown));
    }

    /// @notice policyAdmin(~id) resolves to the base's admin.
    function test_policyAdmin_success_invertResolvesBaseAdmin(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));
        uint64 base = _createAllowlist(admin, policyAdmin);
        assertEq(policyRegistry.policyAdmin(base | INVERT_BIT), policyAdmin);
    }

    // ============================================================
    //                    invertPolicy() HELPER
    // ============================================================

    /// @notice invertPolicy toggles the invert flag and is involutive.
    function test_invertPolicy_success_togglesAndRoundTrips(uint64 base) public pure {
        uint64 inverted = B20Constants.invertPolicy(base);
        assertEq(inverted, base ^ INVERT_BIT);
        assertEq(B20Constants.invertPolicy(inverted), base);
    }

    /// @notice The helper produces the same authorization result as setting the bit directly.
    function test_invertPolicy_success_matchesRawBitOnAuthorization(address account) public {
        uint64 base = _createAllowlist();
        _addAllowlistMember(base, account);
        assertEq(
            policyRegistry.isAuthorized(B20Constants.invertPolicy(base), account),
            policyRegistry.isAuthorized(base | INVERT_BIT, account)
        );
    }

    // ============================================================
    //                 invertedPolicyId() VIEW
    // ============================================================

    /// @notice The registry view toggles the invert flag, is involutive, and never reverts —
    ///         including for unknown/malformed IDs (it reads no state).
    function test_invertedPolicyId_success_togglesAndRoundTrips(uint64 base) public view {
        uint64 inverted = policyRegistry.invertedPolicyId(base);
        assertEq(inverted, base ^ INVERT_BIT);
        assertEq(policyRegistry.invertedPolicyId(inverted), base);
    }

    /// @notice The view agrees with the on-chain `B20Constants.invertPolicy` helper.
    function test_invertedPolicyId_success_matchesLibraryHelper(uint64 base) public view {
        assertEq(policyRegistry.invertedPolicyId(base), B20Constants.invertPolicy(base));
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
