// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20StablecoinRoleConstantsTest is B20StablecoinTest {
    /// @notice Verifies Stablecoin exposes the shared OPERATOR_ROLE constant
    /// @dev Pins the shared selector and role value on the Stablecoin variant.
    function test_OPERATOR_ROLE_success_matchesExpected() public view {
        assertEq(token.OPERATOR_ROLE(), keccak256("OPERATOR_ROLE"), "OPERATOR_ROLE digest");
        assertEq(token.OPERATOR_ROLE(), B20Constants.OPERATOR_ROLE, "OPERATOR_ROLE library value");
    }
}
