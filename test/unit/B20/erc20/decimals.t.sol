// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";
import {IB20} from "src/interfaces/IB20.sol";

contract B20DecimalsTest is B20Test {
    /// @notice Verifies security-token decimals are fixed at 6
    function test_decimals_success_returnsCreationDecimals() public view {
        assertEq(token.decimals(), 6, "security token decimals must be 6");
    }

    /// @notice Verifies decimals are fixed independent of per-token address entropy
    function test_decimals_success_fixedAcrossDifferentTokenAddresses() public {
        address token2 = _createSecurity(alice, keccak256("different-salt"), _securityParams(), new bytes[](0));
        assertEq(token.decimals(), 6, "first security token decimals must be 6");
        assertEq(IB20(token2).decimals(), 6, "second security token decimals must be 6");
    }
}
