// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20RenounceLastAdminTest is B20Test {
    /// @notice Verifies renounceLastAdmin reverts when caller does not hold DEFAULT_ADMIN_ROLE
    /// @dev    Distinct from NotSoleAdmin: the caller isn't an admin at all,
    ///         so authorization fails before the "are you the only one?" check.
    ///         Checks AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE).
    function test_renounceLastAdmin_revert_callerNotAdmin(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.renounceLastAdmin();
    }

    /// @notice Verifies renounceLastAdmin reverts when caller is an admin but additional admins exist
    /// @dev    The function exists exclusively to transition single-admin → zero-admin.
    ///         Callers that want to step away while leaving the token administered should
    ///         use renounceRole (which only allows non-last admins to renounce themselves).
    ///         Checks NotSoleAdmin() error.
    function test_renounceLastAdmin_revert_multipleAdmins(address otherAdmin) public {
        _assumeValidActor(otherAdmin);
        vm.assume(otherAdmin != admin);

        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin);

        vm.prank(admin);
        vm.expectRevert(IB20.NotSoleAdmin.selector);
        token.renounceLastAdmin();
    }

    /// @notice Verifies renounceLastAdmin clears DEFAULT_ADMIN_ROLE from the caller
    /// @dev    Read-after-write: hasRole(DEFAULT_ADMIN_ROLE, msg.sender) is false post-call.
    ///         Paired slot assertion: the `roles[DEFAULT_ADMIN_ROLE][admin]`
    ///         slot reads back as zero.
    function test_renounceLastAdmin_success_clearsAdminRole() public {
        assertTrue(
            token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin),
            "precondition: admin holds B20Constants.DEFAULT_ADMIN_ROLE"
        );

        vm.prank(admin);
        token.renounceLastAdmin();

        assertFalse(
            token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, admin),
            "admin no longer holds B20Constants.DEFAULT_ADMIN_ROLE"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.roleMembershipSlot(B20Constants.DEFAULT_ADMIN_ROLE, admin))),
            uint256(0),
            "roles[ADMIN][admin] slot must be cleared"
        );
    }

    /// @notice Verifies admin-gated operations revert after renounceLastAdmin
    /// @dev    Permanent-immutability invariant. updatePolicy is the canonical example;
    ///         the same mechanism (no admin holder → AccessControlUnauthorizedAccount on
    ///         any DEFAULT_ADMIN_ROLE-gated call) covers updateSupplyCap and grantRole /
    ///         revokeRole / setRoleAdmin for any role. (updateContractURI / updateName /
    ///         updateSymbol are gated by METADATA_ROLE, not DEFAULT_ADMIN_ROLE, so existing
    ///         METADATA_ROLE holders can keep calling them after renunciation.)
    ///         No test should be able to reinstate an admin after this transition.
    function test_renounceLastAdmin_success_subsequentAdminCallsRevert(bytes32 policyScope, uint64 newPolicyId) public {
        // Use a built-in policy ID so updatePolicy gets past policyExists() and would
        // otherwise succeed; the revert here is from the role check, not policy validation.
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;

        vm.prank(admin);
        token.renounceLastAdmin();

        // The original admin is no longer admin and cannot reach the admin-only setter.
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, admin, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updatePolicy(policyScope, newPolicyId);
    }

    /// @notice Verifies grantRole(DEFAULT_ADMIN_ROLE, ...) cannot succeed post-renunciation
    /// @dev    Explicit test of the "no path back to admin" property. grantRole requires
    ///         the caller to hold the admin role for the target role; with zero admins,
    ///         every grant call (from any caller, for any account) reverts.
    function test_renounceLastAdmin_success_noPathToReinstateAdmin(address wouldBeNewAdmin, address caller) public {
        _assumeValidCaller(caller);

        vm.prank(admin);
        token.renounceLastAdmin();

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.grantRole(B20Constants.DEFAULT_ADMIN_ROLE, wouldBeNewAdmin);
    }

    /// @notice Verifies renounceLastAdmin drives the internal adminCount tracker to zero
    /// @dev    adminCount is internal state with no public getter; it lives
    ///         alone in its own slot (slot 8). We read the slot directly via
    ///         `vm.load` so the test exercises the canonical storage
    ///         layout the Rust impl must match.
    ///
    ///         A buggy impl that cleared the role but left adminCount > 0
    ///         would be otherwise undetectable from the public surface
    ///         (since with no admins, no path that reads adminCount is
    ///         reachable). Directly inspecting storage closes the loop on
    ///         the storage-layout contract. We additionally re-assert the
    ///         `initialized` slot (now disjoint at slot 14) is still set,
    ///         so a buggy renounce that scribbled past adminCount's slot
    ///         and re-opened the factory bootstrap window would be caught
    ///         here too.
    function test_renounceLastAdmin_success_adminCountDrivenToZero() public {
        bytes32 adminCountSlot = MockB20Storage.adminCountSlot();
        assertEq(uint256(vm.load(address(token), adminCountSlot)), 1, "precondition: adminCount is 1");
        _assertInitialized(address(token), "precondition: initialized marker is set");

        vm.prank(admin);
        token.renounceLastAdmin();

        assertEq(uint256(vm.load(address(token), adminCountSlot)), 0, "adminCount must be 0 post-renounce");
        _assertInitialized(address(token), "initialized marker must remain set (renounce only clears adminCount)");
    }

    /// @notice Verifies renounceLastAdmin emits LastAdminRenounced(previousAdmin)
    /// @dev    Canonical emission test for LastAdminRenounced. The standard
    ///         RoleRevoked(DEFAULT_ADMIN_ROLE, caller, caller) is also emitted, but its
    ///         canonical emission test lives in revokeRole.t.sol; this stub asserts
    ///         only the dedicated event.
    function test_renounceLastAdmin_success_emitsLastAdminRenounced() public {
        vm.expectEmit(true, false, false, false, address(token));
        emit IB20.LastAdminRenounced(admin);
        vm.prank(admin);
        token.renounceLastAdmin();
    }
}
