// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20PolicyIdTest is B20Test {
    /// @notice Verifies policyId returns 0 (always-allow built-in) for any unconfigured slot
    /// @dev Default state: newly-created tokens are unrestricted across all policy slots
    function test_policyId_success_zeroByDefault(bytes32 policyType) public {
        // unimplemented
    }

    /// @notice Verifies policyId returns the value most recently set via updatePolicy
    /// @dev Read-after-write for the slot mapping
    function test_policyId_success_reflectsUpdatePolicy(bytes32 policyType, uint64 newPolicyId) public {
        // unimplemented
    }

    /// @notice Verifies policyId accepts arbitrary bytes32 keys, not just the standard constants
    /// @dev User-defined policy types are supported for periphery layering
    function test_policyId_success_arbitraryKeysAllowed(bytes32 customType, uint64 newPolicyId) public {
        // unimplemented
    }
}
