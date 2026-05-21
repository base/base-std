// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "test/lib/BaseTest.sol";

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `ITokenFactory` unit tests, and the
///         parent for token-test bases (`B20Test`, `B20StablecoinTest`)
///         which need factory create helpers in setUp.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the factory handle and the per-variant param
/// builder / create wrapper helpers used by both factory tests and
/// token tests.
contract TokenFactoryTest is BaseTest {
    // -- Precompile handle --
    ITokenFactory internal factory = StdPrecompiles.TOKEN_FACTORY;

    // -- Param builders --

    /// @notice Build a `B20CreateParams` with explicit fields.
    function _b20Params(string memory name_, string memory symbol_, address initialAdmin_)
        internal
        pure
        returns (ITokenFactory.B20CreateParams memory)
    {
        return ITokenFactory.B20CreateParams({version: 1, name: name_, symbol: symbol_, initialAdmin: initialAdmin_});
    }

    /// @notice Build a default `B20CreateParams` (`Test`/`TST`, admin).
    function _b20Params() internal view returns (ITokenFactory.B20CreateParams memory) {
        return _b20Params("Test", "TST", admin);
    }

    /// @notice Build a `B20StablecoinCreateParams` with explicit fields.
    function _stablecoinParams(
        string memory name_,
        string memory symbol_,
        address initialAdmin_,
        string memory currency_
    ) internal pure returns (ITokenFactory.B20StablecoinCreateParams memory) {
        return ITokenFactory.B20StablecoinCreateParams({
            version: 1, name: name_, symbol: symbol_, initialAdmin: initialAdmin_, currency: currency_
        });
    }

    /// @notice Build a default `B20StablecoinCreateParams` (`USD Test`/`USDT`, admin, `USD`).
    function _stablecoinParams() internal view returns (ITokenFactory.B20StablecoinCreateParams memory) {
        return _stablecoinParams("USD Test", "USDT", admin, "USD");
    }

    /// @notice Build a `B20SecurityCreateParams` with explicit fields.
    function _securityParams(
        string memory name_,
        string memory symbol_,
        address initialAdmin_,
        string memory isin_,
        uint256 minimumRedeemable_
    ) internal pure returns (ITokenFactory.B20SecurityCreateParams memory) {
        return ITokenFactory.B20SecurityCreateParams({
            version: 1,
            name: name_,
            symbol: symbol_,
            initialAdmin: initialAdmin_,
            isin: isin_,
            minimumRedeemable: minimumRedeemable_
        });
    }

    /// @notice Build a default `B20SecurityCreateParams` (`Security Test`/`SEC`, admin, sample ISIN).
    function _securityParams() internal view returns (ITokenFactory.B20SecurityCreateParams memory) {
        return _securityParams("Security Test", "SEC", admin, "US0000000000", 0);
    }

    // -- Action wrappers --

    /// @notice Create a default-variant token with explicit caller, salt, params, and init calls.
    function _createDefault(
        address caller,
        bytes32 salt,
        ITokenFactory.B20CreateParams memory params,
        bytes[] memory initCalls
    ) internal returns (address token) {
        vm.prank(caller);
        return factory.createToken(ITokenFactory.TokenVariant.DEFAULT, salt, abi.encode(params), initCalls);
    }

    /// @notice Create a default-variant token with defaults (alice creator, fresh salt, empty init calls).
    function _createDefault() internal returns (address token) {
        return _createDefault(alice, keccak256("default-salt"), _b20Params(), new bytes[](0));
    }

    /// @notice Create a stablecoin-variant token with explicit caller, salt, params, and init calls.
    function _createStablecoin(
        address caller,
        bytes32 salt,
        ITokenFactory.B20StablecoinCreateParams memory params,
        bytes[] memory initCalls
    ) internal returns (address token) {
        vm.prank(caller);
        return factory.createToken(ITokenFactory.TokenVariant.STABLECOIN, salt, abi.encode(params), initCalls);
    }

    /// @notice Create a stablecoin-variant token with defaults.
    function _createStablecoin() internal returns (address token) {
        return _createStablecoin(alice, keccak256("stablecoin-salt"), _stablecoinParams(), new bytes[](0));
    }

    /// @notice Create a security-variant token with explicit caller, salt, params, and init calls.
    function _createSecurity(
        address caller,
        bytes32 salt,
        ITokenFactory.B20SecurityCreateParams memory params,
        bytes[] memory initCalls
    ) internal returns (address token) {
        vm.prank(caller);
        return factory.createToken(ITokenFactory.TokenVariant.SECURITY, salt, abi.encode(params), initCalls);
    }

    /// @notice Create a security-variant token with defaults.
    function _createSecurity() internal returns (address token) {
        return _createSecurity(alice, keccak256("security-salt"), _securityParams(), new bytes[](0));
    }
}
