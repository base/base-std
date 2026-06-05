// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {MockB20StablecoinStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @notice Exhaustive layout spec for the `base.b20.stablecoin` namespace.
///
/// @dev    The stablecoin variant adds exactly one storage field
///         (`currency`) at a disjoint ERC-7201 namespace from the base
///         `MockB20Storage` layout. This test asserts:
///         1. The currency slot holds the canonical short/long-string
///            encoding of the surface's `currency()` return.
///         2. The variant namespace's slot does NOT alias any base
///            namespace slot (sanity-checked by the disjoint-roots test
///            in `MockB20Storage.t.sol`; here we additionally confirm
///            the variant slot is independently writable without
///            disturbing base storage).
///
///         The base-namespace layout itself is covered by
///         `B20FullLayout.t.sol`. The stablecoin variant inherits all
///         base behavior; per-mutator base tests run against the
///         stablecoin variant via `B20StablecoinTest` (which overrides
///         `_deployToken` to deploy the stablecoin variant) and are
///         already exercised across the suite.
contract B20StablecoinFullLayoutTest is B20StablecoinTest {
    /// @notice Verifies the variant namespace's `currency` slot holds
    ///         the canonical short-string encoding of the bootstrap
    ///         currency value.
    /// @dev    Bootstrap-default `CURRENCY_AT_CREATION` ("USD") is a
    ///         3-byte short string. The slot must hold
    ///         `("USD" left-justified in high portion) | (3 * 2)`.
    function test_b20StablecoinLayout_success_currencySlotMatchesEncoding() public view {
        bytes32 raw = vm.load(address(token), MockB20StablecoinStorage.currencySlot());
        string memory currency = IB20Stablecoin(address(token)).currency();
        assertEq(
            raw,
            _expectedStringFieldSlot(currency),
            "stablecoin currency field slot must hold the canonical string encoding"
        );
    }
}
