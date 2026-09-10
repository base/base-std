// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20StablecoinRoleConstantsTest is B20StablecoinTest {
    /// @notice Verifies Stablecoin does not expose the Asset-only OPERATOR_ROLE getter
    /// @dev Pins the separation between Asset operations and shared spending authority.
    function test_OPERATOR_ROLE_revert_notExposed() public view {
        (bool success,) = address(token).staticcall(abi.encodeWithSignature("OPERATOR_ROLE()"));
        assertFalse(success, "Stablecoin must not expose OPERATOR_ROLE");
    }

    /// @notice Verifies Stablecoin exposes the shared AUTHORIZED_SPENDER_ROLE constant
    /// @dev Pins the shared selector and role value on the Stablecoin variant.
    function test_AUTHORIZED_SPENDER_ROLE_success_matchesExpected() public view {
        assertEq(
            token.AUTHORIZED_SPENDER_ROLE(), keccak256("AUTHORIZED_SPENDER_ROLE"), "AUTHORIZED_SPENDER_ROLE digest"
        );
        assertEq(
            token.AUTHORIZED_SPENDER_ROLE(),
            B20Constants.AUTHORIZED_SPENDER_ROLE,
            "AUTHORIZED_SPENDER_ROLE library value"
        );
    }
}
