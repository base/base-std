// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20DecimalsTest is B20Test {
    /// @notice Verifies decimals returns the value passed to the factory at creation
    /// @dev Immutable after creation; should match address byte [11]
    function test_decimals_success_returnsCreationDecimals() public view {
        // The default _b20Params() helper creates a token with decimals 18.
        assertEq(token.decimals(), 18, "decimals must match creation value");
    }

    /// @notice Verifies decimals matches byte [11] of the token's own address
    /// @dev Address-schema invariant: stateless decimals() lookup must agree with storage
    function test_decimals_success_matchesAddressByte() public view {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 byteAt11 = uint8(uint160(address(token)) >> 64);
        assertEq(token.decimals(), byteAt11, "decimals() must equal address byte [11]");
    }
}
