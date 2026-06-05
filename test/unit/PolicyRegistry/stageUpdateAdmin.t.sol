// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryStageUpdateAdminTest is PolicyRegistryTest {
    /// @notice Verifies stageUpdateAdmin reverts when called by any non-admin caller
    /// @dev Access control: only the current admin may stage a transfer; checks Unauthorized() error
    function test_stageUpdateAdmin_revert_unauthorized(address caller, address newAdmin) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        vm.prank(caller);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
    }

    /// @notice Verifies stageUpdateAdmin reverts for an unknown policy id
    /// @dev Built-ins and unknown ids are not administrable; checks PolicyNotFound() error
    function test_stageUpdateAdmin_revert_policyNotFound(address caller, uint64 policyId, address newAdmin) public {
        _assumeValidCaller(caller);
        vm.assume(policyId > 1);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        vm.prank(caller);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
    }

    /// @notice Verifies stageUpdateAdmin sets pendingPolicyAdmin to the nominated address
    /// @dev Pending slot updated; current admin unchanged until finalizeUpdateAdmin.
    ///      Paired slot assertion: `pendingAdmins[id]` slot decodes to
    ///      newAdmin (low 160 bits); `policies[id]` admin lane is unchanged.
    function test_stageUpdateAdmin_success_setsPending(address currentAdmin, address newAdmin) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), newAdmin);
        assertEq(policyRegistry.policyAdmin(policyId), currentAdmin);
        assertEq(
            address(
                uint160(uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(policyId))))
            ),
            newAdmin,
            "pendingAdmins[id] slot must hold the staged candidate"
        );
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(
                uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)))
            ),
            currentAdmin,
            "policies[id] admin lane must remain currentAdmin while staged"
        );
    }

    /// @notice Verifies a second stageUpdateAdmin overwrites a previously-staged candidate
    /// @dev Latest call wins; the prior candidate loses ability to finalize.
    ///      Paired slot assertion: `pendingAdmins[id]` slot reflects only the second value.
    function test_stageUpdateAdmin_success_overwritesPrior(address currentAdmin, address first, address second) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(first != second);
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, first);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, second);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), second);
        assertEq(
            address(
                uint160(uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(policyId))))
            ),
            second,
            "pendingAdmins[id] slot must reflect only the second stage"
        );
    }

    /// @notice Verifies stageUpdateAdmin(address(0)) clears a previously-staged candidate
    /// @dev Explicit cancel path; pendingPolicyAdmin returns address(0) after.
    ///      Paired slot assertion: `pendingAdmins[id]` slot reads back as zero.
    function test_stageUpdateAdmin_success_clearsPending(address currentAdmin, address first) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(first != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, first);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, address(0));
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
        assertEq(
            vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(policyId)),
            bytes32(0),
            "pendingAdmins[id] slot must be cleared after staging zero"
        );
    }

    /// @notice Verifies clearing the pending slot (stage address(0)) causes finalizeUpdateAdmin to revert
    /// @dev Round-trip: stage a candidate, cancel it, confirm finalize no longer works
    function test_stageUpdateAdmin_success_cancelBlocksFinalize(address currentAdmin, address first) public {
        vm.assume(currentAdmin != address(0));
        vm.assume(first != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, first);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, address(0));
        vm.expectRevert(IPolicyRegistry.NoPendingAdmin.selector);
        vm.prank(first);
        policyRegistry.finalizeUpdateAdmin(policyId);
    }

    /// @notice Verifies stageUpdateAdmin emits PolicyAdminStaged with the correct args
    /// @dev Event integrity: policyId, currentAdmin, pendingAdmin match the call
    function test_stageUpdateAdmin_success_emitsPolicyAdminStaged(address currentAdmin, address newAdmin) public {
        vm.assume(currentAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(currentAdmin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminStaged(policyId, currentAdmin, newAdmin);
        vm.prank(currentAdmin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
    }
}
