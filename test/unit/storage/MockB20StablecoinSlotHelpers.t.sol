// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";

import {B20StablecoinTest} from "test/lib/B20StablecoinTest.sol";
import {MockB20StablecoinStorage} from "test/lib/mocks/MockB20Storage.sol";

/// @notice Self-tests for `MockB20StablecoinStorage`'s slot helper.
///
/// @dev    The variant has one stateful field (`currency`); we assert
///         `currencySlot()` locates the slot the factory wrote during
///         bootstrap by decoding the short-string encoding inline.
contract MockB20StablecoinSlotHelpersTest is B20StablecoinTest {
    /// @notice Verifies `currencySlot()` locates the slot the factory
    ///         wrote the currency string to.
    /// @dev    Bootstrap default `currencyAtCreation = "USD"` is a short
    ///         string (3 bytes). Short-string encoding packs the bytes in
    ///         the high portion and `length * 2` in the low byte.
    function test_currencySlot_success_holdsShortStringEncoding() public view {
        bytes32 raw = vm.load(address(token), MockB20StablecoinStorage.currencySlot());

        bytes memory currency = bytes(IB20Stablecoin(address(token)).currency());
        assertTrue(currency.length < 32, "precondition: this test is for short-string encoding");

        assertEq(uint256(raw) & 0xff, currency.length * 2, "low byte must equal length * 2");

        // Reconstruct the high portion: bytes left-justified in the slot
        // (the encoding stores `mload(data + 32)` directly, which is the
        // first 32 bytes of the string's memory body).
        bytes32 expectedHighPortion;
        assembly {
            // We can't mload from `currency` memory pointer directly here
            // because Solidity's `bytes memory` layout reserves the first
            // word for the length, so the body starts at `currency + 32`.
            expectedHighPortion := mload(add(currency, 32))
        }
        // Compose: high portion OR low byte (length * 2).
        bytes32 expected = bytes32(uint256(expectedHighPortion) | (currency.length * 2));
        assertEq(raw, expected, "currencySlot must hold the short-string encoding of currency()");
    }
}
