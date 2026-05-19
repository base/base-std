// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20StablecoinTest} from "test/lib/B20StablecoinTest.sol";

contract B20StablecoinCurrencyTest is B20StablecoinTest {
    /// @notice Verifies currency returns the string passed to the factory at creation
    /// @dev Immutable readback; should equal `currencyAtCreation` set in setUp
    function test_currency_success_returnsCreationCurrency() public {
        // unimplemented
    }
}
