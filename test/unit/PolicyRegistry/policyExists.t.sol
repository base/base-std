// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryPolicyExistsTest is PolicyRegistryTest {
    /// @notice Verifies policyExists returns true for built-in id 0
    /// @dev Always-allow built-in is always present
    function test_policyExists_success_builtinZero() public {
        // unimplemented
    }

    /// @notice Verifies policyExists returns true for built-in id type(uint64).max
    /// @dev Always-reject built-in is always present
    function test_policyExists_success_builtinMax() public {
        // unimplemented
    }

    /// @notice Verifies policyExists returns false for any id that has not been created
    /// @dev Fuzz across the custom id space outside the issued range
    function test_policyExists_success_falseForUncreated(uint64 policyId) public {
        // unimplemented
    }

    /// @notice Verifies policyExists returns true for a freshly-created policy id
    /// @dev Existence flips immediately on createPolicy
    function test_policyExists_success_trueAfterCreate(uint8 policyTypeInt) public {
        // unimplemented
    }
}
