// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";

import {MockB20} from "test/lib/mocks/MockB20.sol";
import {MockB20StablecoinStorage} from "test/lib/mocks/MockB20Storage.sol";

/// @title MockB20Stablecoin
/// @notice Reference implementation of the `IB20Stablecoin` variant.
///         Extends `MockB20` with a single immutable `currency()`
///         identifier; all other variant behavior is inherited unchanged.
///
/// @dev    Variant-specific state lives in `MockB20StablecoinStorage`'s
///         own ERC-7201 namespace (`base.b20.stablecoin`), disjoint from
///         the base `MockB20Storage` namespace (`base.b20`), so the
///         variant composes additively without touching the base's slot
///         layout.
///
///         The `currency` value is set in the variant-specific
///         `_bootstrapVariant` override during factory creation; once
///         the bootstrap window closes there is no mutator.
contract MockB20Stablecoin is MockB20, IB20Stablecoin {
    /// @notice The immutable currency identifier (e.g. "USD", "EUR",
    ///         "XAU"). Set at creation by the factory's
    ///         `_bootstrapVariant` dispatch with `abi.encode(string)`.
    function currency() external view returns (string memory) {
        return MockB20StablecoinStorage.layout().currency;
    }

    /// @notice Variant-specific bootstrap hook. Decodes a single
    ///         `string` (the currency identifier) from `variantData`
    ///         and writes it into variant storage.
    /// @dev    Called exactly once, from `bootstrap()` on the base
    ///         contract during factory creation, before any `initCalls`
    ///         dispatch.
    function _bootstrapVariant(bytes calldata variantData) internal override {
        string memory currency_ = abi.decode(variantData, (string));
        MockB20StablecoinStorage.layout().currency = currency_;
    }
}
