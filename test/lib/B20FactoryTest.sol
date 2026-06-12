// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "base-std-test/lib/BaseTest.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

/// @notice Base test contract for `IB20Factory` unit tests, and the
///         parent for token-test bases (`B20Test`, `B20StablecoinTest`)
///         which need factory create helpers in setUp.
///
/// Inherits all precompile-mock etch wiring and common actors from
/// `BaseTest`; adds the factory handle and the per-variant param
/// builder / create wrapper helpers used by both factory tests and
/// token tests.
contract B20FactoryTest is BaseTest {
    // -- Precompile handle --
    IB20Factory internal factory = StdPrecompiles.B20_FACTORY;

    // -- Param builders --

    /// @notice Build a `B20StablecoinCreateParams` with explicit fields.
    function _stablecoinParams(
        string memory name_,
        string memory symbol_,
        address initialAdmin_,
        string memory currency_
    ) internal pure returns (IB20Factory.B20StablecoinCreateParams memory) {
        return IB20Factory.B20StablecoinCreateParams({
            version: B20FactoryLib.B20_STABLECOIN_CREATE_PARAMS_VERSION,
            name: name_,
            symbol: symbol_,
            initialAdmin: initialAdmin_,
            currency: currency_
        });
    }

    /// @notice Build a default `B20StablecoinCreateParams` (`USD Test`/`USDT`, admin, `USD`).
    function _stablecoinParams() internal view returns (IB20Factory.B20StablecoinCreateParams memory) {
        return _stablecoinParams("USD Test", "USDT", admin, "USD");
    }

    /// @notice Build a `B20AssetCreateParams` with explicit fields.
    /// @dev    Tests that don't care about `decimals` should call the
    ///         no-arg overload (which pins `decimals = MIN_ASSET_DECIMALS`
    ///         to match historical behavior). Tests that DO care thread the
    ///         explicit value through here.
    function _assetParams(string memory name_, string memory symbol_, address initialAdmin_, uint8 decimals_)
        internal
        pure
        returns (IB20Factory.B20AssetCreateParams memory)
    {
        return IB20Factory.B20AssetCreateParams({
            version: B20FactoryLib.B20_ASSET_CREATE_PARAMS_VERSION,
            name: name_,
            symbol: symbol_,
            initialAdmin: initialAdmin_,
            decimals: decimals_
        });
    }

    /// @notice Build a `B20AssetCreateParams` with the default decimals (`MIN_ASSET_DECIMALS`).
    function _assetParams(string memory name_, string memory symbol_, address initialAdmin_)
        internal
        pure
        returns (IB20Factory.B20AssetCreateParams memory)
    {
        return _assetParams(name_, symbol_, initialAdmin_, B20Constants.MIN_ASSET_DECIMALS);
    }

    /// @notice Build a default `B20AssetCreateParams` (`Asset Test`/`SEC`, admin, `MIN_ASSET_DECIMALS`).
    function _assetParams() internal view returns (IB20Factory.B20AssetCreateParams memory) {
        return _assetParams("Asset Test", "AST", admin);
    }

    // -- Action wrappers --

    /// @notice Create a stablecoin-variant token with explicit caller, salt, params, and init calls.
    function _createStablecoin(
        address caller,
        bytes32 salt,
        IB20Factory.B20StablecoinCreateParams memory params,
        bytes[] memory initCalls
    ) internal returns (address token) {
        vm.prank(caller);
        return factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(params), initCalls);
    }

    /// @notice Create a stablecoin-variant token with defaults.
    function _createStablecoin() internal returns (address token) {
        return _createStablecoin(alice, keccak256("stablecoin-salt"), _stablecoinParams(), new bytes[](0));
    }

    /// @notice Create a asset-variant token with explicit caller, salt, params, and init calls.
    function _createAsset(
        address caller,
        bytes32 salt,
        IB20Factory.B20AssetCreateParams memory params,
        bytes[] memory initCalls
    ) internal returns (address token) {
        vm.prank(caller);
        return factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(params), initCalls);
    }

    /// @notice Create a asset-variant token with defaults.
    function _createAsset() internal returns (address token) {
        return _createAsset(alice, keccak256("asset-salt"), _assetParams(), new bytes[](0));
    }

    // ============================================================
    //                  INITIALIZED-MARKER ASSERTION
    // ============================================================

    /// @notice Asserts `token` was initialized by the factory, working in
    ///         both mock and live-precompile worlds.
    /// @dev    The two impls mark "this B20 has been brought to life by
    ///         the factory" through different mechanisms:
    ///
    ///         - **Mock world** (default): `MockB20Factory` writes `1`
    ///           directly via `vm.store` to a dedicated storage slot at
    ///           the end of the B-20 storage layout
    ///           (`MockB20Storage.initializedSlot()`). The mock has no
    ///           bytecode-stub mechanism — token addresses get the full
    ///           `MockB20` runtimeCode etched, and the bootstrap window
    ///           is gated on the slot's value.
    ///
    ///         - **Live precompile world** (`LIVE_PRECOMPILES=true`):
    ///           the Rust factory precompile calls `set_code(token, [0xef])`,
    ///           planting a single-byte stub at the token address. The
    ///           Rust `is_initialized` check is just `!info.is_empty_code_hash()`
    ///           (see `crates/common/precompile-storage/src/provider.rs`).
    ///           `0xef` is the EIP-3541-reserved opcode prefix, so the
    ///           only way an address picks up that bytecode is via the
    ///           factory's privileged `set_code` — making it an
    ///           unforgeable "this is a live B-20" marker. The Rust
    ///           `B20TokenStorage` layout has no `initialized` field
    ///           at all; the dedicated mock slot would alias to
    ///           `mint_policy_ids` on the Rust side, which is actively
    ///           used for something else.
    ///
    ///         Tests that pin the bootstrap-window-closed state should
    ///         use this helper instead of reading the slot directly, so
    ///         the same test body is meaningful under both backends.
    ///         Tests that specifically pin the SOLIDITY MOCK's slot
    ///         layout (e.g. `MockB20SlotHelpers.t.sol`) should
    ///         `vm.skip(livePrecompiles)` instead —
    ///         those assertions are inherently mock-world invariants.
    function _assertInitialized(address token, string memory err) internal view {
        if (livePrecompiles) {
            assertGt(token.code.length, 0, err);
        } else {
            assertEq(uint256(vm.load(token, MockB20Storage.initializedSlot())), 1, err);
        }
    }
}
