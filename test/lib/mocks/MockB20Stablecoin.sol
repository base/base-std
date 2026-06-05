// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {MockB20} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20StablecoinStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @title MockB20Stablecoin
/// @notice Reference implementation of the `IB20Stablecoin` variant.
///         Extends `MockB20` with a single immutable `currency()`
///         code; all other variant behavior is inherited unchanged.
///
/// @dev    Variant-specific state lives in `MockB20StablecoinStorage`'s
///         own ERC-7201 namespace (`base.b20.stablecoin`), disjoint from
///         the base `MockB20Storage` namespace (`base.b20`), so the
///         variant composes additively without touching the base's slot
///         layout.
///
///         The `currency` value is written directly by the factory
///         (via `vm.store` at the variant namespace's `CURRENCY_OFFSET`)
///         during creation; there is no init function and no mutator.
contract MockB20Stablecoin is MockB20, IB20Stablecoin {
    /// @notice Stablecoin-variant decimals are fixed at 6.
    function decimals() external pure override(MockB20, IB20) returns (uint8) {
        return 6;
    }

    /// @notice The immutable currency code (e.g. "USD", "EUR",
    ///         "XAU"). Written by the factory at creation.
    function currency() external view returns (string memory) {
        return MockB20StablecoinStorage.layout().currency;
    }
}
