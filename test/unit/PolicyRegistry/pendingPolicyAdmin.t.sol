// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";
import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPendingPolicyAdminTest is PolicyRegistryTest {
    /// @notice Verifies pendingPolicyAdmin returns address(0) before any transfer is staged
    /// @dev Default state for a freshly-created policy
    function test_pendingPolicyAdmin_success_defaultZero() public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns the address most recently staged
    /// @dev Read-after-write for stageUpdateAdmin
    function test_pendingPolicyAdmin_success_returnsStaged(address newAdmin) public {
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), newAdmin);
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) after finalizeUpdateAdmin
    /// @dev Pending slot is cleared once the transfer completes
    function test_pendingPolicyAdmin_success_zeroAfterFinalize(address newAdmin) public {
        vm.assume(newAdmin != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, newAdmin);
        vm.prank(newAdmin);
        policyRegistry.finalizeUpdateAdmin(policyId);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) after renounceAdmin
    /// @dev In-flight transfers are invalidated as a side effect of renouncement
    function test_pendingPolicyAdmin_success_zeroAfterRenounce(address pending) public {
        vm.assume(pending != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin);
        policyRegistry.stageUpdateAdmin(policyId, pending);
        vm.prank(admin);
        policyRegistry.renounceAdmin(policyId);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) for built-in policies
    /// @dev Built-ins have no admin and therefore no pending admin
    function test_pendingPolicyAdmin_success_zeroForBuiltins() public view {
        assertEq(policyRegistry.pendingPolicyAdmin(0), address(0));
        assertEq(policyRegistry.pendingPolicyAdmin(1), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) for an uncreated id
    function test_pendingPolicyAdmin_success_zeroForUncreated(uint64 seed) public view {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) for a malformed id
    function test_pendingPolicyAdmin_success_zeroForMalformedId(uint64 seed) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertEq(policyRegistry.pendingPolicyAdmin(policyId), address(0));
    }

    /// @notice Verifies the built-in short-circuit holds even when the underlying
    ///         `pendingAdmins[builtin]` storage slot is poisoned with a non-zero value
    /// @dev    Defense-in-depth pin. Without the short-circuit in `pendingPolicyAdmin`,
    ///         a corrupted built-in pending-admin slot would leak through the view. The
    ///         function MUST return `address(0)` for built-in IDs regardless of storage
    ///         state, matching the Rust precompile's gated read at
    ///         `crates/common/precompiles/src/policy/storage.rs` (`pending_policy_admin`).
    ///
    ///         Mock-only: `vm.store` cannot write to native precompile addresses, so this
    ///         test is skipped when running against live precompiles.
    function test_pendingPolicyAdmin_success_zeroForBuiltinsEvenWithStoragePoison() public {
        // Skip when running against live precompiles — vm.store cannot target native precompiles.
        vm.skip(livePrecompiles);
        address poison = address(0xDEAD);
        vm.store(
            address(policyRegistry),
            MockPolicyRegistryStorage.pendingAdminSlot(PolicyRegistryConstants.ALWAYS_ALLOW_ID),
            bytes32(uint256(uint160(poison)))
        );
        vm.store(
            address(policyRegistry),
            MockPolicyRegistryStorage.pendingAdminSlot(PolicyRegistryConstants.ALWAYS_BLOCK_ID),
            bytes32(uint256(uint160(poison)))
        );
        assertEq(policyRegistry.pendingPolicyAdmin(PolicyRegistryConstants.ALWAYS_ALLOW_ID), address(0));
        assertEq(policyRegistry.pendingPolicyAdmin(PolicyRegistryConstants.ALWAYS_BLOCK_ID), address(0));
    }
}
