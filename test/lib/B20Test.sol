// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenFactoryTest} from "test/lib/TokenFactoryTest.sol";

import {IB20} from "src/interfaces/IB20.sol";

/// @notice Base test contract for `IB20` unit tests.
///
/// Extends `TokenFactoryTest` because an IB20 token cannot exist
/// without the factory: `setUp` calls `super.setUp()` to etch every
/// precompile mock (via `BaseTest`) and pick up the factory create
/// helpers, then deploys a default-variant token here so the token's
/// identity bytes (variant byte at address `[10]`, decimals byte at
/// `[11]`) match the real address schema. In live mode under
/// `--fork-url`, the same flow hits the real precompile factory.
///
/// On top of the inherited factory actors, this contract adds the
/// token-specific role-holders (`minter`, `burner`, `pauser`,
/// `unpauser`, `burnBlocker`) so role-gated tests have explicit named
/// accounts to grant roles to in setUp's initCalls.
contract B20Test is TokenFactoryTest {
    // -- Token-specific role-holder actors --
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal burnBlocker = makeAddr("burnBlocker");

    // -- Token under test --
    /// @notice Default-variant `IB20` token deployed in `setUp`.
    IB20 internal token;

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();

        vm.label(minter, "minter");
        vm.label(burner, "burner");
        vm.label(pauser, "pauser");
        vm.label(unpauser, "unpauser");
        vm.label(burnBlocker, "burnBlocker");

        token = _deployToken();
        vm.label(address(token), "token");
    }

    /// @notice Token-deployment hook. Default impl deploys a default-variant
    ///         token via the factory mock; variant-specific bases (e.g.
    ///         `B20StablecoinTest`) override to deploy their variant while
    ///         reusing every other piece of `B20Test`.
    /// @dev    The current `MockTokenFactory` only computes and returns the
    ///         deterministic token address — no token code is deployed
    ///         there yet, so any call against `token` (transfer, mint, ...)
    ///         will revert. The unit stubs in this spec PR have no-op
    ///         bodies, so this is intentional. The next PR plants real
    ///         token bytecode at the returned address.
    function _deployToken() internal virtual returns (IB20) {
        return IB20(_createDefault());
    }

    /// @notice Wraps a single `PausableFeature` in a length-1 array for
    ///         `pause` / `unpause` calls. Saves the 3 lines of array
    ///         construction Solidity requires for memory arrays.
    function _singleFeature(IB20.PausableFeature feature)
        internal
        pure
        returns (IB20.PausableFeature[] memory features)
    {
        features = new IB20.PausableFeature[](1);
        features[0] = feature;
    }
}
