// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPolicyAdminTest is PolicyRegistryTest {
    /// @notice Verifies policyAdmin reverts for an unknown policy id
    /// @dev Lookup guard for non-existent ids; checks PolicyNotFound() error
    function test_policyAdmin_revert_policyNotFound(uint64 policyId) public {
        // unimplemented
    }

    /// @notice Verifies policyAdmin returns address(0) for built-in policies
    /// @dev Built-ins have no admin; both id 0 and id type(uint64).max return zero
    function test_policyAdmin_success_zeroForBuiltins() public {
        // unimplemented
    }

    /// @notice Verifies policyAdmin returns the admin nominated at creation time
    /// @dev Initial-admin readback
    function test_policyAdmin_success_returnsAssigned(address admin_) public {
        // unimplemented
    }

    /// @notice Verifies policyAdmin returns address(0) after renounceAdmin
    /// @dev Post-renounce: admin slot is permanently cleared
    function test_policyAdmin_success_zeroAfterRenounce(address admin_) public {
        // unimplemented
    }
}
