// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract PolicyRegistryPolicyAdminTest is PolicyRegistryTest {
    /// @notice Verifies policyAdmin returns address(0) for a well-formed but uncreated id
    /// @dev Lookup miss returns zero rather than reverting.
    function test_policyAdmin_success_zeroForUncreated(uint64 seed) public view {
        uint64 policyId = _wellFormedUncreatedPolicyId(seed);
        assertEq(policyRegistry.policyAdmin(policyId), address(0));
    }

    /// @notice Verifies policyAdmin returns address(0) for a malformed id
    /// @dev Malformed-ID short-circuit returns zero.
    function test_policyAdmin_success_zeroForMalformedId(uint64 seed) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertEq(policyRegistry.policyAdmin(policyId), address(0));
    }

    /// @notice Verifies policyAdmin returns address(0) for built-in sentinels.
    function test_policyAdmin_success_zeroForBuiltins() public view {
        assertEq(policyRegistry.policyAdmin(PolicyRegistryConstants.ALWAYS_ALLOW_ID), address(0));
        assertEq(policyRegistry.policyAdmin(PolicyRegistryConstants.ALWAYS_BLOCK_ID), address(0));
    }

    /// @notice Verifies policyAdmin returns the admin nominated at creation time
    /// @dev Initial-admin readback
    function test_policyAdmin_success_returnsAssigned(address admin_) public {
        vm.assume(admin_ != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertEq(policyRegistry.policyAdmin(policyId), admin_);
    }

    /// @notice Verifies policyAdmin returns address(0) after renounceAdmin
    /// @dev Post-renounce: admin slot is permanently cleared
    function test_policyAdmin_success_zeroAfterRenounce(address admin_) public {
        vm.assume(admin_ != address(0));
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
        vm.prank(admin_);
        policyRegistry.renounceAdmin(policyId);
        assertEq(policyRegistry.policyAdmin(policyId), address(0));
    }
}
