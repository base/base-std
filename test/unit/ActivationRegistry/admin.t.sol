// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ActivationRegistryTest} from "base-std-test/lib/ActivationRegistryTest.sol";

contract ActivationRegistryAdminTest is ActivationRegistryTest {
    /// @notice Verifies admin returns the configured activation admin address
    /// @dev Constant readback; the mock-vs-live boundary returns the same address either way.
    ///      The setUp-resolved `activationAdmin` is the same value the mock hardcodes
    ///      (`0xCB00…0000`), so a second readback must agree.
    function test_admin_success_returnsConfigured() public view {
        assertEq(activationRegistry.admin(), activationAdmin, "admin() must return the address resolved during setUp");
        assertTrue(activationAdmin != address(0), "activation admin must be non-zero");
    }
}
