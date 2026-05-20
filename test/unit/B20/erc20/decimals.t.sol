// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20DecimalsTest is B20Test {
    /// @notice Verifies default-token decimals are fixed at 18
    function test_decimals_success_returnsCreationDecimals() public view {
        assertEq(token.decimals(), 18, "default token decimals must be 18");
    }

    /// @notice Verifies address byte [11] is reserved and no longer drives decimals
    function test_decimals_success_reservedByteIgnored() public view {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt11 = uint8(uint160(address(token)) >> 64);
        assertEq(byteAt11, 0, "address byte [11] is reserved and must be zero");
        assertEq(token.decimals(), 18, "decimals() must remain fixed at 18");
    }
}
