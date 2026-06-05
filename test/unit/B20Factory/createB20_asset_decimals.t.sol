// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";

import {MockB20} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

/// @notice Coverage for the asset variant's configurable `decimals` field.
///
/// @dev Asserts the boundary values, the out-of-range revert with the new
///      `InvalidDecimals(uint8)` error, fuzz coverage over the full
///      below-min / above-max / in-range ranges, the `B20Created` event's
///      `decimals` field reflecting the input, the storage round-trip via
///      the `MockB20AssetStorage.decimalsSlot()` paired-slot pattern,
///      and the stablecoin variant's regression-free hardcoded `6`.
contract B20FactoryCreateB20AssetDecimalsTest is B20FactoryTest {
    /*//////////////////////////////////////////////////////////////
                         OUT-OF-RANGE REVERTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the just-below-min point case (`5`) reverts with `InvalidDecimals(5)`.
    function test_createB20_revert_decimals_justBelowMin(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        uint8 bad = B20Constants.MIN_ASSET_DECIMALS - 1;
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, bad);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.InvalidDecimals.selector, bad));
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Verifies the just-above-max point case (`19`) reverts with `InvalidDecimals(19)`.
    function test_createB20_revert_decimals_justAboveMax(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        uint8 bad = B20Constants.MAX_ASSET_DECIMALS + 1;
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, bad);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.InvalidDecimals.selector, bad));
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Fuzzes the entire below-min range `[0, MIN_ASSET_DECIMALS - 1]` and asserts
    ///         the factory reverts with `InvalidDecimals(decimals)` on every value.
    function test_createB20_revert_decimals_belowMin_fuzz(address caller, bytes32 salt, uint8 decimalsSeed) public {
        _assumeValidCaller(caller);
        uint8 bad = uint8(bound(uint256(decimalsSeed), 0, uint256(B20Constants.MIN_ASSET_DECIMALS) - 1));
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, bad);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.InvalidDecimals.selector, bad));
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }

    /// @notice Fuzzes the entire above-max range `[MAX_ASSET_DECIMALS + 1, type(uint8).max]`
    ///         and asserts the factory reverts with `InvalidDecimals(decimals)` on every value.
    function test_createB20_revert_decimals_aboveMax_fuzz(address caller, bytes32 salt, uint8 decimalsSeed) public {
        _assumeValidCaller(caller);
        uint8 bad =
            uint8(bound(uint256(decimalsSeed), uint256(B20Constants.MAX_ASSET_DECIMALS) + 1, uint256(type(uint8).max)));
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, bad);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.InvalidDecimals.selector, bad));
        factory.createB20(IB20Factory.B20Variant.ASSET, salt, abi.encode(p), new bytes[](0));
    }

    /*//////////////////////////////////////////////////////////////
                          BOUNDARY SUCCESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the lower-bound boundary value `MIN_ASSET_DECIMALS` (`6`) succeeds
    ///         and the deployed token reports it from `decimals()`.
    function test_createB20_success_decimals_lowerBound(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p =
            _assetParams("Asset Test", "AST", admin, B20Constants.MIN_ASSET_DECIMALS);
        address token = _createAsset(caller, salt, p, new bytes[](0));
        assertEq(
            MockB20(token).decimals(), B20Constants.MIN_ASSET_DECIMALS, "decimals() must equal MIN_ASSET_DECIMALS (6)"
        );
    }

    /// @notice Verifies the upper-bound boundary value `MAX_ASSET_DECIMALS` (`18`) succeeds
    ///         and the deployed token reports it from `decimals()`.
    function test_createB20_success_decimals_upperBound(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p =
            _assetParams("Asset Test", "AST", admin, B20Constants.MAX_ASSET_DECIMALS);
        address token = _createAsset(caller, salt, p, new bytes[](0));
        assertEq(
            MockB20(token).decimals(), B20Constants.MAX_ASSET_DECIMALS, "decimals() must equal MAX_ASSET_DECIMALS (18)"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          IN-RANGE FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Fuzzes the entire allowed range `[MIN_ASSET_DECIMALS, MAX_ASSET_DECIMALS]`
    ///         and asserts creation succeeds and `decimals()` round-trips the input.
    function test_createB20_success_decimals_inRange_fuzz(address caller, bytes32 salt, uint8 decimalsSeed) public {
        _assumeValidCaller(caller);
        uint8 good = uint8(
            bound(
                uint256(decimalsSeed),
                uint256(B20Constants.MIN_ASSET_DECIMALS),
                uint256(B20Constants.MAX_ASSET_DECIMALS)
            )
        );
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, good);
        address token = _createAsset(caller, salt, p, new bytes[](0));
        assertEq(MockB20(token).decimals(), good, "decimals() must round-trip the in-range fuzzed input");
    }

    /*//////////////////////////////////////////////////////////////
                         STORAGE ROUND-TRIP
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the factory writes `decimals` to the canonical slot
    ///         (`MockB20AssetStorage.decimalsSlot()`) so the storage value
    ///         matches both the input and `decimals()` on every in-range value.
    /// @dev    Paired-slot pattern: the surface read AND the raw `vm.load` both
    ///         match the fuzz input.
    function test_createB20_success_decimals_storageRoundTrip(address caller, bytes32 salt, uint8 decimalsSeed) public {
        _assumeValidCaller(caller);
        uint8 good = uint8(
            bound(
                uint256(decimalsSeed),
                uint256(B20Constants.MIN_ASSET_DECIMALS),
                uint256(B20Constants.MAX_ASSET_DECIMALS)
            )
        );
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, good);
        address token = _createAsset(caller, salt, p, new bytes[](0));

        assertEq(
            uint256(vm.load(token, MockB20AssetStorage.decimalsSlot())),
            uint256(good),
            "decimalsSlot must hold the factory-written decimals byte"
        );
        assertEq(MockB20(token).decimals(), good, "decimals() surface must match the slot value");
    }

    /*//////////////////////////////////////////////////////////////
                       EVENT-VS-STATE COHERENCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the `B20Created` event's `decimals` field equals the input value
    ///         on every in-range fuzz input.
    /// @dev    `expectEmit`-level pin with a fuzzed value.
    function test_createB20_success_emitsB20Created_asset_decimals(address caller, bytes32 salt, uint8 decimalsSeed)
        public
    {
        _assumeValidCaller(caller);
        uint8 good = uint8(
            bound(
                uint256(decimalsSeed),
                uint256(B20Constants.MIN_ASSET_DECIMALS),
                uint256(B20Constants.MAX_ASSET_DECIMALS)
            )
        );
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, good);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.ASSET, caller, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit IB20Factory.B20Created(predicted, IB20Factory.B20Variant.ASSET, "Asset Test", "AST", good, bytes(""));
        _createAsset(caller, salt, p, new bytes[](0));
    }

    /// @notice Decodes the `B20Created` event from the recorded logs and asserts its
    ///         `decimals` field equals `token.decimals()` (the deployed token's surface).
    /// @dev    Decode-level pin (complementary to the `expectEmit` pin above): catches a
    ///         regression where the event payload and the storage write would diverge.
    function test_createB20_success_b20CreatedDecimals_decodes(address caller, bytes32 salt, uint8 decimalsSeed)
        public
    {
        _assumeValidCaller(caller);
        uint8 good = uint8(
            bound(
                uint256(decimalsSeed),
                uint256(B20Constants.MIN_ASSET_DECIMALS),
                uint256(B20Constants.MAX_ASSET_DECIMALS)
            )
        );
        IB20Factory.B20AssetCreateParams memory p = _assetParams("Asset Test", "AST", admin, good);

        vm.recordLogs();
        address token = _createAsset(caller, salt, p, new bytes[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 selector = IB20Factory.B20Created.selector;
        uint8 eventDecimals;
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == selector) {
                // B20Created data payload: (name, symbol, decimals, variantEventParams).
                (,, eventDecimals,) = abi.decode(logs[i].data, (string, string, uint8, bytes));
                found = true;
                break;
            }
        }
        assertTrue(found, "B20Created event must be emitted");
        assertEq(eventDecimals, good, "event decimals must equal the input");
        assertEq(MockB20(token).decimals(), eventDecimals, "event decimals must equal token.decimals()");
    }

    /*//////////////////////////////////////////////////////////////
                     STABLECOIN REGRESSION SANITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the stablecoin variant still hardcodes `decimals() == 6`.
    /// @dev Configurable decimals is an asset-only change; the stablecoin path must be untouched.
    function test_createB20_success_stablecoin_decimalsStillHardcoded(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        address token = _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        assertEq(MockB20(token).decimals(), 6, "stablecoin decimals must remain hardcoded at 6");
    }
}
