// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryNextPolicyIdTest is PolicyRegistryTest {
    /// @notice Verifies nextPolicyId starts at 1 (id 0 reserved for the always-allow built-in)
    /// @dev Initial state check before any policy creations
    function test_nextPolicyId_success_startsAtOne() public {
        // unimplemented
    }

    /// @notice Verifies nextPolicyId advances by one per successful createPolicy call
    /// @dev Monotonic counter; checks the returned id equals the prior nextPolicyId value
    function test_nextPolicyId_success_advancesPerCreate(uint8 count) public {
        // unimplemented
    }
}
