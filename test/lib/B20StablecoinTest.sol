// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

/// @notice Base test contract for `IB20Stablecoin` unit tests.
///
/// Extends `B20Test` for the inherited test surface (actors, labels,
/// setUp wiring, the `_singleFeature` helper, the stablecoin-variant
/// token deployed by `_deployToken`). The only stablecoin-specific
/// concern at the base level is the currency string tests will compare
/// against, which `B20Test` cannot know about.
///
/// The inherited `token` member is typed `IB20`. Tests that need the
/// variant-only method (`currency()`) cast inline:
///   `IB20Stablecoin(address(token)).currency()`
contract B20StablecoinTest is B20Test {
    /// @notice The currency identifier baked into the bootstrap-default
    ///         `_stablecoinParams()` and therefore the value
    ///         `IB20Stablecoin(address(token)).currency()` returns
    ///         after `_deployToken`. Tests reference this constant
    ///         instead of hardcoding "USD" so a single edit retargets
    ///         every assertion.
    string internal constant CURRENCY_AT_CREATION = "USD";
}
