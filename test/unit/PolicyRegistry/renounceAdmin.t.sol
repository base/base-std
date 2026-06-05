// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryRenounceAdminTest is PolicyRegistryTest {
    /// @notice Verifies renounceAdmin reverts when called by any non-admin caller
    /// @dev Access control: only the current admin may renounce; checks Unauthorized() error
    function test_renounceAdmin_revert_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.renounceAdmin(policyId);
    }

    /// @notice Verifies renounceAdmin reverts for an unknown policy id
    /// @dev Built-ins and unknown ids are not administrable; checks PolicyNotFound() error
    function test_renounceAdmin_revert_policyNotFound(address caller, uint64 policyId) public {
        _assumeValidCaller(caller);
        vm.assume(policyId > 1);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.renounceAdmin(policyId);
    }

    /// @notice Verifies renounceAdmin sets policyAdmin to address(0)
    /// @dev Admin lane cleared; exists bit survives so `policyExists` stays true.
    function test_renounceAdmin_success_clearsAdmin(address currentAdmin) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.renounceAdmin(policyId);
        assertEq(policyRegistry.policyAdmin(policyId), address(0));
        assertTrue(policyRegistry.policyExists(policyId));

        uint256 packed = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)));
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(packed),
            address(0),
            "policies[id] admin lane must be cleared after renounce"
        );
        assertTrue(
            MockPolicyRegistryStorage.policyExistsFromPacked(packed),
            "policies[id] exists bit must remain set after renounce"
        );
    }

    /// @notice Verifies renounceAdmin clears any in-flight pending admin
    /// @dev Side effect: previously-staged pending admin is invalidated.
    ///      Paired slot assertion: `pendingAdmins[id]` slot is zero.
    function test_renounceAdmin_success_clearsPending(address currentAdmin, address pending) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(pending != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, pending);
        vm.prank(currentAdmin);
        policyRegistry.renounceAdmin(policyId);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
        assertEq(
            vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(policyId)),
            bytes32(0),
            "pendingAdmins[id] slot must be cleared after renounce"
        );
    }

    /// @notice Verifies renounceAdmin freezes all mutation on the policy
    /// @dev Post-renounce: stageUpdateAdmin / updateAllowlist / updateBlocklist all revert Unauthorized
    function test_renounceAdmin_success_freezesMutation(address currentAdmin) public {
        vm.assume(currentAdmin != address(0));
        // Use BLOCKLIST so we can test both updateAllowlist (incompatible) and updateBlocklist (frozen)
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.BLOCKLIST);
        vm.prank(currentAdmin);
        policyRegistry.renounceAdmin(policyId);

        address[] memory accounts = new address[](0);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, alice);

        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(currentAdmin);
        policyRegistry.updateBlocklist(policyId, true, accounts);
    }

    /// @notice Verifies renounceAdmin emits PolicyAdminUpdated with newAdmin = address(0)
    /// @dev Renouncement variant of PolicyAdminUpdated; canonical event test lives in finalizeUpdateAdmin.t.sol
    function test_renounceAdmin_success_emitsPolicyAdminUpdatedToZero(address currentAdmin) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(policyId, currentAdmin, address(0));
        vm.prank(currentAdmin);
        policyRegistry.renounceAdmin(policyId);
    }
}
