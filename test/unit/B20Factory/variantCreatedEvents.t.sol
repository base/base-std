// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20Factory} from "src/interfaces/IB20Factory.sol";

import {B20FactoryTest} from "test/lib/B20FactoryTest.sol";

/// @notice Tests for the variant-specific companion events `StablecoinCreated` and
///         `AssetCreated` emitted immediately after `B20Created` in the same
///         transaction. These events carry the immutable per-variant fields
///         (`currency`, `isin`) that are not included in `B20Created` itself,
///         enabling stream-based indexers to populate variant-specific columns
///         without making mid-handler view calls.
contract B20FactoryVariantCreatedEventsTest is B20FactoryTest {
    // ============================================================
    //                     StablecoinCreated
    // ============================================================

    /// @notice StablecoinCreated is emitted after B20Created with the correct currency.
    function test_createB20_success_emitsStablecoinCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("USD Coin", "USDC", admin, "USD");
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, caller, salt);

        vm.expectEmit(true, false, false, true, address(factory));
        emit IB20Factory.StablecoinCreated(predicted, "USD");
        _createStablecoin(caller, salt, p, new bytes[](0));
    }

    /// @notice StablecoinCreated carries the exact currency string written at creation.
    function test_createB20_success_stablecoinCreatedCurrencyMatchesParams(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("Euro Coin", "EUROC", admin, "EUR");
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, caller, salt);

        vm.expectEmit(true, false, false, true, address(factory));
        emit IB20Factory.StablecoinCreated(predicted, "EUR");
        _createStablecoin(caller, salt, p, new bytes[](0));
    }

    /// @notice StablecoinCreated is emitted in the same transaction as B20Created, after it.
    function test_createB20_success_stablecoinCreatedEmittedAfterB20Created(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("JPY Coin", "JPYC", admin, "JPY");
        address predicted = factory.getB20Address(IB20Factory.B20Variant.STABLECOIN, caller, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit IB20Factory.B20Created(predicted, IB20Factory.B20Variant.STABLECOIN, "JPY Coin", "JPYC", 6);
        vm.expectEmit(true, false, false, true, address(factory));
        emit IB20Factory.StablecoinCreated(predicted, "JPY");
        _createStablecoin(caller, salt, p, new bytes[](0));
    }

    /// @notice Creating a DEFAULT variant does NOT emit StablecoinCreated.
    function test_createB20_success_defaultVariantDoesNotEmitStablecoinCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.recordLogs();
        _createDefault(caller, salt, _b20Params(), new bytes[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 stablecoinSig = IB20Factory.StablecoinCreated.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != stablecoinSig, "StablecoinCreated must not fire for DEFAULT variant");
        }
    }

    /// @notice Creating a ASSET variant does NOT emit StablecoinCreated.
    function test_createB20_success_securityVariantDoesNotEmitStablecoinCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.recordLogs();
        _createSecurity(caller, salt, _securityParams(), new bytes[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 stablecoinSig = IB20Factory.StablecoinCreated.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != stablecoinSig, "StablecoinCreated must not fire for ASSET variant");
        }
    }

    // ============================================================
    //                      AssetCreated
    // ============================================================

    /// @notice AssetCreated is emitted after B20Created with the correct ISIN.
    function test_createB20_success_emitsAssetCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p =
            _securityParams("Apple Inc.", "AAPL", admin, APPLE_ISIN, 0);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.ASSET, caller, salt);

        vm.expectEmit(true, false, false, true, address(factory));
        emit IB20Factory.AssetCreated(predicted, APPLE_ISIN);
        _createSecurity(caller, salt, p, new bytes[](0));
    }

    /// @notice AssetCreated carries the exact ISIN string written at creation.
    function test_createB20_success_securityCreatedIsinMatchesParams(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p =
            _securityParams("Security Test", "SEC", admin, DEFAULT_ISIN, 0);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.ASSET, caller, salt);

        vm.expectEmit(true, false, false, true, address(factory));
        emit IB20Factory.AssetCreated(predicted, DEFAULT_ISIN);
        _createSecurity(caller, salt, p, new bytes[](0));
    }

    /// @notice AssetCreated is emitted in the same transaction as B20Created, after it.
    function test_createB20_success_securityCreatedEmittedAfterB20Created(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        IB20Factory.B20AssetCreateParams memory p =
            _securityParams("Apple Inc.", "AAPL", admin, APPLE_ISIN, 0);
        address predicted = factory.getB20Address(IB20Factory.B20Variant.ASSET, caller, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit IB20Factory.B20Created(predicted, IB20Factory.B20Variant.ASSET, "Apple Inc.", "AAPL", 6);
        vm.expectEmit(true, false, false, true, address(factory));
        emit IB20Factory.AssetCreated(predicted, APPLE_ISIN);
        _createSecurity(caller, salt, p, new bytes[](0));
    }

    /// @notice Creating a DEFAULT variant does NOT emit AssetCreated.
    function test_createB20_success_defaultVariantDoesNotEmitAssetCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.recordLogs();
        _createDefault(caller, salt, _b20Params(), new bytes[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 securitySig = IB20Factory.AssetCreated.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != securitySig, "AssetCreated must not fire for DEFAULT variant");
        }
    }

    /// @notice Creating a STABLECOIN variant does NOT emit AssetCreated.
    function test_createB20_success_stablecoinVariantDoesNotEmitAssetCreated(address caller, bytes32 salt) public {
        _assumeValidCaller(caller);
        vm.recordLogs();
        _createStablecoin(caller, salt, _stablecoinParams(), new bytes[](0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 securitySig = IB20Factory.AssetCreated.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != securitySig, "AssetCreated must not fire for STABLECOIN variant");
        }
    }
}
