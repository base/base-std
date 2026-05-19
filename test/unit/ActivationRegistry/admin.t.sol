// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryAdminTest is ActivationRegistryTest {
    /// @notice Verifies admin returns the configured activation admin address
    /// @dev Constant readback; the mock-vs-live boundary returns the same address either way
    function test_admin_success_returnsConfigured() public {
        // unimplemented
    }
}
