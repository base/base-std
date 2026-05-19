// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";

/// @notice Base test contract for `IB20Stablecoin` unit tests.
///
/// Only the variant-specific additions on `IB20Stablecoin` are covered
/// here; the inherited `IB20` surface is exercised against a
/// default-variant token in `B20Test`. The `IB20Stablecoin` test
/// surface today is a single function (`currency()`), so the base is
/// intentionally minimal.
///
/// `setUp` is mock-vs-live aware. The mock contracts are added in a
/// follow-up PR; until then, `token` is the zero address and the unit
/// stubs in this spec PR are not yet implemented, so this is intentional.
contract B20StablecoinTest is Test {
    // -- Actors --
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    // -- Token under test --
    /// @notice Stablecoin-variant `IB20Stablecoin` token deployed in `setUp`.
    IB20Stablecoin internal token;

    /// @notice The currency identifier passed at creation (e.g. "USD").
    /// Set in `setUp` so tests can compare against `token.currency()`.
    string internal currencyAtCreation;

    // -- Setup --
    function setUp() public virtual {
        vm.label(admin, "admin");
        vm.label(alice, "alice");
        vm.label(attacker, "attacker");

        currencyAtCreation = "USD";

        // TODO(mock PR): etch MockTokenFactory at StdPrecompiles.TOKEN_FACTORY_ADDRESS
        // (mock-mode only) and deploy a stablecoin-variant token here via the factory
        // with `currencyAtCreation` as the currency string. Assign the returned address
        // to `token` and `vm.label` it. Live mode under --fork-url skips the etch.
    }
}
