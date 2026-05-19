// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Stablecoin} from "src/interfaces/IB20Stablecoin.sol";

/// @notice Base test contract for `IB20Stablecoin` unit tests.
///
/// Extends `B20Test` because `IB20Stablecoin is IB20`: the inherited
/// surface (`_transfer`, `_mint`, `_burn`, role helpers, pause helpers,
/// ...) is exactly the same against a stablecoin-variant token, and
/// every B20 actor / label / setUp step applies unchanged. The only
/// stablecoin-specific concern at the base level is the variant of the
/// deployed token, which `_deployToken` controls.
///
/// The inherited `token` member is typed `IB20`. Tests that need the
/// variant-only methods (just `currency()` today) use `_stablecoinToken()`
/// or cast inline. The stablecoin test surface is small enough that
/// this is rarely needed.
///
/// The mock contracts are added in a follow-up PR; until then,
/// `_deployToken` returns the zero address. The unit stubs in this
/// spec PR are not yet implemented, so this is intentional.
contract B20StablecoinTest is B20Test {
    /// @notice The currency identifier passed at creation (e.g. "USD").
    /// Tests compare against `_stablecoinToken().currency()`.
    string internal currencyAtCreation = "USD";

    /// @notice Typed accessor for the inherited `token`, cast as `IB20Stablecoin`.
    function _stablecoinToken() internal view returns (IB20Stablecoin) {
        return IB20Stablecoin(address(token));
    }

    /// @inheritdoc B20Test
    /// @dev Override deploys a stablecoin-variant token instead of the
    ///      default variant. TODO(mock PR): swap the placeholder for a
    ///      real `_createStablecoin(...)` call once MockTokenFactory is
    ///      etched.
    function _deployToken() internal virtual override returns (IB20) {
        return IB20(address(0));
    }
}
