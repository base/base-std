// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";

import {IB20} from "base-std/interfaces/IB20.sol";

/// @notice Base test contract for `IB20Stablecoin` unit tests.
///
/// Extends `B20Test` because `IB20Stablecoin is IB20`: the inherited
/// surface (actors, labels, setUp wiring, the `_singleFeature` helper)
/// applies unchanged to a stablecoin-variant token. The only
/// stablecoin-specific concerns at the base level are the variant of the
/// deployed token, which `_deployToken` controls, and the currency
/// string the test will compare against.
///
/// The inherited `token` member is typed `IB20`. Tests that need the
/// variant-only method (`currency()`) cast inline:
///   `IB20Stablecoin(address(token)).currency()`
contract B20StablecoinTest is B20Test {
    /// @notice The currency code baked into the bootstrap-default
    ///         `_stablecoinParams()` and therefore the value
    ///         `IB20Stablecoin(address(token)).currency()` returns
    ///         after `_deployToken`. Tests reference this constant
    ///         instead of hardcoding "USD" so a single edit retargets
    ///         every assertion.
    string internal constant CURRENCY_AT_CREATION = "USD";

    /// @inheritdoc B20Test
    /// @dev Override deploys a stablecoin-variant token via the factory mock.
    ///      The factory etches `MockB20Stablecoin` runtime bytecode at the
    ///      computed address, seeds `currency` directly via vm.store, grants
    ///      the initial admin, then closes the bootstrap window.
    function _deployToken() internal virtual override returns (IB20) {
        return IB20(_createStablecoin());
    }
}
