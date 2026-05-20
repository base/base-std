// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";
import {IB20} from "src/interfaces/IB20.sol";

contract B20DecimalsTest is B20Test {
    /// @notice Verifies default-token decimals are fixed at 18
    function test_decimals_success_returnsCreationDecimals() public view {
        assertEq(token.decimals(), 18, "default token decimals must be 18");
    }

    /// @notice Verifies decimals are fixed independent of per-token address entropy
    function test_decimals_success_fixedAcrossDifferentTokenAddresses() public {
        address token2 = _createDefault(alice, keccak256("different-salt"), _b20Params(), new bytes[](0));
        assertEq(token.decimals(), 18, "first default token decimals must be 18");
        assertEq(IB20(token2).decimals(), 18, "second default token decimals must be 18");
    }
}
