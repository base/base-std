// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenFactoryTest} from "test/lib/TokenFactoryTest.sol";

import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";

/// @notice Base test contract for `IB20Stablecoin` unit tests.
///
/// Extends `TokenFactoryTest` because a stablecoin token cannot exist
/// without the factory: `setUp` calls `super.setUp()` to etch every
/// precompile mock (via `BaseTest`) and pick up the factory create
/// helpers, then deploys a stablecoin-variant token here.
///
/// Only the variant-specific additions on `IB20Stablecoin` are covered
/// here; the inherited `IB20` surface is exercised against a
/// default-variant token in `B20Test`. The `IB20Stablecoin` test
/// surface today is a single function (`currency()`), so the helper
/// area is intentionally empty.
///
/// The mock contracts are added in a follow-up PR; until then, `token`
/// is the zero address and the unit stubs in this spec PR are not yet
/// implemented, so this is intentional.
contract B20StablecoinTest is TokenFactoryTest {
    // -- Token under test --
    /// @notice Stablecoin-variant `IB20Stablecoin` token deployed in `setUp`.
    IB20Stablecoin internal token;

    /// @notice The currency identifier passed at creation (e.g. "USD").
    /// Set in `setUp` so tests can compare against `token.currency()`.
    string internal currencyAtCreation;

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();

        currencyAtCreation = "USD";

        // TODO(mock PR): once MockTokenFactory is etched (in BaseTest.setUp),
        // call `_createStablecoin(...)` with `currencyAtCreation` as the currency
        // string. Cast the returned address to IB20Stablecoin and assign to `token`;
        // then `vm.label` it.
    }
}
