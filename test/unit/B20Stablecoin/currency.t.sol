// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";

contract B20StablecoinCurrencyTest is B20StablecoinTest {
    /// @notice Verifies currency returns the string passed to the factory at creation
    /// @dev Immutable readback; should equal `CURRENCY_AT_CREATION` (the
    ///      string baked into the bootstrap-default `_stablecoinParams()`).
    function test_currency_success_returnsCreationCurrency() public view {
        assertEq(
            IB20Stablecoin(address(token)).currency(),
            CURRENCY_AT_CREATION,
            "currency() must match the value passed at creation"
        );
    }
}
