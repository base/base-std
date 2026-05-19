// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Base test contract for `ITokenFactory` unit tests.
///
/// `setUp` is mock-vs-live aware: the etch is skipped when the canonical
/// precompile address already has code (live mode under `--fork-url`).
/// In mock mode the mock contract is etched at the canonical address so
/// the same test body executes against either backend without branching.
///
/// The mock contract is added in a follow-up PR; until then, calls to
/// the factory revert at runtime under mock mode. The unit stubs in this
/// spec PR are not yet implemented, so this is intentional.
contract TokenFactoryTest is Test {
    // -- Actors --
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    // -- Precompile handle --
    ITokenFactory internal factory = StdPrecompiles.TOKEN_FACTORY;

    // -- Setup --
    function setUp() public virtual {
        vm.label(StdPrecompiles.TOKEN_FACTORY_ADDRESS, "TokenFactory");
        vm.label(admin, "admin");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(attacker, "attacker");

        // TODO(mock PR): if (StdPrecompiles.TOKEN_FACTORY_ADDRESS.code.length == 0) {
        //     vm.etch(StdPrecompiles.TOKEN_FACTORY_ADDRESS, type(MockTokenFactory).runtimeCode);
        // }
    }

    // -- Param builders --

    /// @notice Build a `B20CreateParams` with explicit fields.
    function _b20Params(string memory name_, string memory symbol_, address initialAdmin_, uint8 decimals_)
        internal
        pure
        returns (ITokenFactory.B20CreateParams memory)
    {
        return ITokenFactory.B20CreateParams({
            version: 1,
            name: name_,
            symbol: symbol_,
            initialAdmin: initialAdmin_,
            decimals: decimals_
        });
    }

    /// @notice Build a default `B20CreateParams` (`Test`/`TST`, admin, 18 decimals).
    function _b20Params() internal view returns (ITokenFactory.B20CreateParams memory) {
        return _b20Params("Test", "TST", admin, 18);
    }

    /// @notice Build a `B20StablecoinCreateParams` with explicit fields.
    function _stablecoinParams(
        string memory name_,
        string memory symbol_,
        address initialAdmin_,
        string memory currency_
    ) internal pure returns (ITokenFactory.B20StablecoinCreateParams memory) {
        return ITokenFactory.B20StablecoinCreateParams({
            version: 1,
            name: name_,
            symbol: symbol_,
            initialAdmin: initialAdmin_,
            currency: currency_
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
