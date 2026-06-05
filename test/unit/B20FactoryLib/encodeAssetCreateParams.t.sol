// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeAssetCreateParamsTest is B20FactoryLibTest {
    /// @notice Verifies the output decodes back to a `B20AssetCreateParams`
    ///         with the caller's fields and the current version byte.
    /// @dev    Round-trips through `abi.decode` to pin the wire format the
    ///         factory's asset decode arm consumes.
    function test_encodeAssetCreateParams_success_roundTripsThroughDecode(
        string memory name,
        string memory symbol,
        address initialAdmin,
        uint8 decimals
    ) public pure {
        bytes memory blob = B20FactoryLib.encodeAssetCreateParams(name, symbol, initialAdmin, decimals);
        IB20Factory.B20AssetCreateParams memory decoded = abi.decode(blob, (IB20Factory.B20AssetCreateParams));

        assertEq(
            decoded.version, B20FactoryLib.B20_ASSET_CREATE_PARAMS_VERSION, "version byte must match library constant"
        );
        assertEq(decoded.name, name, "name must round-trip");
        assertEq(decoded.symbol, symbol, "symbol must round-trip");
        assertEq(decoded.initialAdmin, initialAdmin, "initialAdmin must round-trip");
        assertEq(decoded.decimals, decimals, "decimals must round-trip");
    }

    /// @notice Verifies the encoded blob is byte-identical to a hand-encoded
    ///         `B20AssetCreateParams` struct.
    /// @dev    Pins the encoding shape so future field reordering on the
    ///         struct is caught against an explicit reference.
    function test_encodeAssetCreateParams_success_matchesHandEncodedStruct(
        string memory name,
        string memory symbol,
        address initialAdmin,
        uint8 decimals
    ) public pure {
        bytes memory expected = abi.encode(
            IB20Factory.B20AssetCreateParams({
                version: B20FactoryLib.B20_ASSET_CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                decimals: decimals
            })
        );
        bytes memory actual = B20FactoryLib.encodeAssetCreateParams(name, symbol, initialAdmin, decimals);
        assertEq(actual, expected, "encoded blob must match hand-encoded struct byte-for-byte");
    }

    /// @notice Verifies the library's current asset create-params version is `1`.
    /// @dev    Pins the constant so a future bump is intentional and visible in diff.
    function test_b20AssetCreateParamsVersion_pinned() public pure {
        assertEq(uint256(B20FactoryLib.B20_ASSET_CREATE_PARAMS_VERSION), 1, "version must be 1");
    }
}
