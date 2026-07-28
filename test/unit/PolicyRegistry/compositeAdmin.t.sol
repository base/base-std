// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Admin lifecycle (`stageUpdateAdmin` -> `finalizeUpdateAdmin`, `renounceAdmin`) exercised
///         against COMPOSITE policies (UNION / INTERSECT).
///
/// @dev Composites reuse the same admin machinery as simple policies — the same packed admin lane,
///      the same pending slot, the same events. The per-function files
///      (`stageUpdateAdmin.t.sol` / `finalizeUpdateAdmin.t.sol` / `renounceAdmin.t.sol`) pin that
///      machinery against ALLOWLIST / BLOCKLIST targets; this file re-runs the load-bearing cases
///      against a composite target so a future divergence in the composite code path (a separate
///      dispatch arm, a type guard added to the admin functions) is caught.
///
///      Every test opens with `_skipIfNoComposite()`: composites are a `PolicyRegistry` V2 feature
///      and the live Beryl/V1 precompile rejects both composite selectors outright, so the whole
///      contract self-skips in that world rather than failing.
contract PolicyRegistryCompositeAdminTest is PolicyRegistryTest {
    // ============================================================
    //                       STAGE (CA-1)
    // ============================================================

    /// @notice Verifies the composite admin can stage another account as pending admin
    /// @dev CA-1. Mirrors `stageUpdateAdmin.t.sol::test_stageUpdateAdmin_success_setsPending` with a
    ///      composite target: the pending slot is populated and the active admin lane is untouched
    ///      until finalize. Paired slot assertions confirm the composite writes the same
    ///      `pendingAdmins[id]` / `policies[id]` lanes a simple policy does.
    function test_stageUpdateAdmin_success_onComposite(uint8 typeIdx, address newAdmin) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, newAdmin);

        assertEq(policyRegistry.pendingPolicyAdmin(composite), newAdmin, "composite pending admin must be the nominee");
        assertEq(policyRegistry.policyAdmin(composite), admin, "composite admin must not change on stage");
        assertEq(
            address(
                uint160(
                    uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(composite)))
                )
            ),
            newAdmin,
            "pendingAdmins[composite] slot must hold the staged candidate"
        );
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(
                uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(composite)))
            ),
            admin,
            "policies[composite] admin lane must remain the current admin while staged"
        );
    }

    /// @notice Verifies staging over an existing nomination on a composite replaces it
    /// @dev CA-1 / EV-17. Second stage wins: the first nominee is dropped from the pending slot and
    ///      can no longer finalize (it now reads as a non-pending caller -> `Unauthorized`).
    function test_stageUpdateAdmin_success_secondStageWinsOnComposite(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, alice);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, bob);

        assertEq(policyRegistry.pendingPolicyAdmin(composite), bob, "second nomination must replace the first");

        // The displaced nominee cannot claim the composite.
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(alice);
        policyRegistry.finalizeUpdateAdmin(composite);

        // The live nominee can.
        vm.prank(bob);
        policyRegistry.finalizeUpdateAdmin(composite);
        assertEq(policyRegistry.policyAdmin(composite), bob, "the surviving nominee must become admin");
    }

    // ============================================================
    //                      FINALIZE (CA-2)
    // ============================================================

    /// @notice Verifies the staged account can finalize and becomes the composite's admin
    /// @dev CA-2. Mirrors `finalizeUpdateAdmin.t.sol` promote + clear against a composite: the
    ///      packed admin lane is promoted to the nominee and the pending slot is zeroed. The new
    ///      admin's authority is proven behaviorally by a successful `updateComposite`, which the
    ///      old admin can no longer perform.
    function test_finalizeUpdateAdmin_success_onComposite(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, alice);
        vm.prank(alice);
        policyRegistry.finalizeUpdateAdmin(composite);

        assertEq(policyRegistry.policyAdmin(composite), alice, "composite admin must be promoted to the nominee");
        assertEq(policyRegistry.pendingPolicyAdmin(composite), address(0), "pending slot must clear on finalize");
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(
                uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(composite)))
            ),
            alice,
            "policies[composite] admin lane must be promoted to the nominee"
        );
        assertEq(
            vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(composite)),
            bytes32(0),
            "pendingAdmins[composite] slot must be cleared after finalize"
        );

        // The rotation transferred real authority over the composite, not just the getter value.
        uint64[] memory newChildren = _makeSimpleChildren(2);
        vm.prank(admin);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.updateComposite(composite, newChildren);

        vm.prank(alice);
        policyRegistry.updateComposite(composite, newChildren);
    }

    // ============================================================
    //                    ACCESS CONTROL (CA-3)
    // ============================================================

    /// @notice Verifies a non-admin cannot stage an admin transfer on a composite
    /// @dev CA-3. Same guard and same error as the simple path
    ///      (`stageUpdateAdmin.t.sol::test_stageUpdateAdmin_revert_unauthorized`): only the current
    ///      admin may nominate, everyone else gets `Unauthorized()`.
    function test_stageUpdateAdmin_revert_unauthorized_onComposite(address caller, uint8 typeIdx, address newAdmin)
        public
    {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.stageUpdateAdmin(composite, newAdmin);
    }

    /// @notice Verifies a non-staged account cannot finalize a composite's in-flight transfer
    /// @dev CA-3. With a nomination in flight, the pending-slot precondition is satisfied, so the
    ///      auth guard is what fires: any caller other than the nominee — including the current
    ///      admin — gets `Unauthorized()`, matching
    ///      `finalizeUpdateAdmin.t.sol::test_finalizeUpdateAdmin_revert_unauthorized`.
    function test_finalizeUpdateAdmin_revert_unauthorized_onComposite(address caller, uint8 typeIdx) public {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        vm.assume(caller != alice);
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, alice);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.finalizeUpdateAdmin(composite);
    }

    /// @notice Verifies finalizing a composite with no nomination in flight reverts NoPendingAdmin
    /// @dev CA-3. The other half of the "cannot finalize" case: with an empty pending slot the
    ///      precondition check fires before the auth check, so even the sitting admin gets
    ///      `NoPendingAdmin()` rather than `Unauthorized()` — same ordering as the simple path in
    ///      `finalizeUpdateAdmin.t.sol::test_finalizeUpdateAdmin_revert_noPendingAdmin`.
    function test_finalizeUpdateAdmin_revert_noPendingAdmin_onComposite(address caller, uint8 typeIdx) public {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.expectRevert(IPolicyRegistry.NoPendingAdmin.selector);
        vm.prank(caller);
        policyRegistry.finalizeUpdateAdmin(composite);
    }

    // ============================================================
    //                      RENOUNCE (CA-4)
    // ============================================================

    /// @notice Verifies renouncing a composite freezes it without killing its evaluation
    /// @dev CA-4. After `renounceAdmin` the composite is admin-less (`policyAdmin` == 0) but still a
    ///      real policy (`policyExists` true) that keeps gating traffic. The evaluation half is
    ///      proven behaviorally rather than by a getter: a member seeded into every child before the
    ///      renounce is still authorized afterwards, and a non-member is still denied — so the gate
    ///      is genuinely re-evaluating the child set, not degenerating to allow-all. Seeding all
    ///      children keeps the assertion valid for both UNION and INTERSECT.
    function test_renounceAdmin_success_onComposite(uint8 typeIdx, address member, address stranger) public {
        _skipIfNoComposite();
        vm.assume(member != address(0));
        vm.assume(stranger != member);

        uint64[] memory children = _makeSimpleChildren(2);
        uint64 composite = policyRegistry.createCompositePolicy(admin, _creatableCompositeType(typeIdx), children);

        // Seed `member` into every child so the verdict is `true` under UNION and INTERSECT alike.
        address[] memory one = new address[](1);
        one[0] = member;
        for (uint256 i = 0; i < children.length; ++i) {
            vm.prank(admin);
            policyRegistry.updateAllowlist(children[i], true, one);
        }
        assertTrue(policyRegistry.isAuthorized(composite, member), "member must be authorized before renounce");

        vm.prank(admin);
        policyRegistry.renounceAdmin(composite);

        assertEq(policyRegistry.policyAdmin(composite), address(0), "composite admin lane must be cleared");
        assertTrue(policyRegistry.policyExists(composite), "renounced composite must still exist");
        assertTrue(
            policyRegistry.isAuthorized(composite, member),
            "renounced composite must still authorize a member of its child set"
        );
        assertFalse(
            policyRegistry.isAuthorized(composite, stranger),
            "renounced composite must still deny a non-member (frozen, not allow-all)"
        );
    }

    /// @notice Verifies a renounced composite is permanently unadministrable by every caller
    /// @dev CA-4. `updateComposite.t.sol::test_updateComposite_revert_renouncedComposite` pins the
    ///      former admin; this fuzzes the caller across the whole address space to show the freeze
    ///      is global rather than a one-address lockout, and extends the same assertion to
    ///      `stageUpdateAdmin` / `renounceAdmin` so no admin-lifecycle entry point can revive the
    ///      composite. All three fail closed with `Unauthorized()` because the admin lane is zero
    ///      and no caller can ever match it.
    function test_renounceAdmin_success_freezesCompositeForEveryCaller(address caller, uint8 typeIdx) public {
        _skipIfNoComposite();
        _assumeValidCaller(caller);
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        vm.prank(admin);
        policyRegistry.renounceAdmin(composite);

        uint64[] memory children = _makeSimpleChildren(2);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.updateComposite(composite, children);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.stageUpdateAdmin(composite, caller);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.renounceAdmin(composite);
    }

    // ============================================================
    //                       EVENTS (EV-16)
    // ============================================================

    /// @notice Verifies staging an admin on a composite emits PolicyAdminStaged
    /// @dev EV-16. Identical signature and args to the simple path: (composite id, current admin,
    ///      nominee). The composite id in `topics[1]` carries the UNION/INTERSECT type byte, which
    ///      is what makes this worth asserting separately from the simple-policy test.
    function test_stageUpdateAdmin_success_emitsPolicyAdminStagedOnComposite(uint8 typeIdx, address newAdmin) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminStaged(composite, admin, newAdmin);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, newAdmin);
    }

    /// @notice Verifies finalizing on a composite emits PolicyAdminUpdated(id, previous, new)
    /// @dev EV-16. The promotion variant of `PolicyAdminUpdated`, with both address topics non-zero.
    function test_finalizeUpdateAdmin_success_emitsPolicyAdminUpdatedOnComposite(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(composite, alice);

        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(composite, admin, alice);
        vm.prank(alice);
        policyRegistry.finalizeUpdateAdmin(composite);
    }

    /// @notice Verifies renouncing a composite emits PolicyAdminUpdated(id, admin, address(0))
    /// @dev EV-16. The renunciation variant: `newAdmin == address(0)` is the on-chain marker that a
    ///      composite has been frozen, so indexers depend on this exact arg shape.
    function test_renounceAdmin_success_emitsPolicyAdminUpdatedToZeroOnComposite(uint8 typeIdx) public {
        _skipIfNoComposite();
        uint64 composite = _createComposite(_creatableCompositeType(typeIdx), 2);

        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(composite, admin, address(0));
        vm.prank(admin);
        policyRegistry.renounceAdmin(composite);
    }
}
