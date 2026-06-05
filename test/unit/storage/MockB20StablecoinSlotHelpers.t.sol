// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {MockB20StablecoinStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @notice Self-tests for `MockB20StablecoinStorage`'s slot helper.
///
/// @dev    The variant has one stateful field (`currency`); we assert
///         `currencySlot()` locates the slot the factory wrote during
///         bootstrap by recomputing the expected encoding via the
///         `_expectedStringFieldSlot` helper on `BaseTest`.
contract MockB20StablecoinSlotHelpersTest is B20StablecoinTest {
    /// @notice Verifies `currencySlot()` locates the slot the factory
    ///         wrote the currency string to.
    /// @dev    Bootstrap-default `CURRENCY_AT_CREATION` ("USD") is a
    ///         short string (3 bytes). The expected encoding is
    ///         computed via the shared `_expectedStringFieldSlot`
    ///         helper so this test exercises the slot location without
    ///         re-deriving the short/long string layout.
    function test_currencySlot_success_holdsExpectedEncoding() public view {
        bytes32 raw = vm.load(address(token), MockB20StablecoinStorage.currencySlot());
        string memory currency = IB20Stablecoin(address(token)).currency();
        assertEq(
            raw,
            _expectedStringFieldSlot(currency),
            "currencySlot must hold the canonical string encoding of currency()"
        );
    }
}
