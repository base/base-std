// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20DecimalsTest is B20Test {
    /// @notice Verifies decimals returns the value passed to the factory at creation
    /// @dev Immutable after creation; should match address byte [11]
    function test_decimals_success_returnsCreationDecimals() public {
        // unimplemented
    }

    /// @notice Verifies decimals matches byte [11] of the token's own address
    /// @dev Address-schema invariant: stateless decimals() lookup must agree with storage
    function test_decimals_success_matchesAddressByte() public {
        // unimplemented
    }
}
