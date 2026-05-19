// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPendingPolicyAdminTest is PolicyRegistryTest {
    /// @notice Verifies pendingPolicyAdmin returns address(0) before any transfer is staged
    /// @dev Default state for a freshly-created policy
    function test_pendingPolicyAdmin_success_defaultZero() public {
        // unimplemented
    }

    /// @notice Verifies pendingPolicyAdmin returns the address most recently staged
    /// @dev Read-after-write for stageUpdateAdmin
    function test_pendingPolicyAdmin_success_returnsStaged(address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) after finalizeUpdateAdmin
    /// @dev Pending slot is cleared once the transfer completes
    function test_pendingPolicyAdmin_success_zeroAfterFinalize(address newAdmin) public {
        // unimplemented
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) after renounceAdmin
    /// @dev In-flight transfers are invalidated as a side effect of renouncement
    function test_pendingPolicyAdmin_success_zeroAfterRenounce(address pending) public {
        // unimplemented
    }

    /// @notice Verifies pendingPolicyAdmin returns address(0) for built-in policies
    /// @dev Built-ins have no admin and therefore no pending admin
    function test_pendingPolicyAdmin_success_zeroForBuiltins() public {
        // unimplemented
    }
}
