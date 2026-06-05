// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeStablecoinCreateParamsTest is B20FactoryLibTest {
    /// @notice Verifies the output decodes back to a `B20StablecoinCreateParams`
    ///         with the caller's fields and the current version byte.
    /// @dev    Round-trips through `abi.decode` to pin the wire format the
    ///         factory's stablecoin decode arm consumes.
    function test_encodeStablecoinCreateParams_success_roundTripsThroughDecode(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory currency
    ) public pure {
        bytes memory blob = B20FactoryLib.encodeStablecoinCreateParams(name, symbol, initialAdmin, currency);
        IB20Factory.B20StablecoinCreateParams memory decoded = abi.decode(blob, (IB20Factory.B20StablecoinCreateParams));

        assertEq(
            decoded.version,
            B20FactoryLib.B20_STABLECOIN_CREATE_PARAMS_VERSION,
            "version byte must match library constant"
        );
        assertEq(decoded.name, name, "name must round-trip");
        assertEq(decoded.symbol, symbol, "symbol must round-trip");
        assertEq(decoded.initialAdmin, initialAdmin, "initialAdmin must round-trip");
        assertEq(decoded.currency, currency, "currency must round-trip");
    }

    /// @notice Verifies the encoded blob is byte-identical to a hand-encoded
    ///         `B20StablecoinCreateParams` struct.
    /// @dev    Pins the encoding shape so future field reordering on the
    ///         struct is caught against an explicit reference.
    function test_encodeStablecoinCreateParams_success_matchesHandEncodedStruct(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory currency
    ) public pure {
        bytes memory expected = abi.encode(
            IB20Factory.B20StablecoinCreateParams({
                version: B20FactoryLib.B20_STABLECOIN_CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                currency: currency
            })
        );
        bytes memory actual = B20FactoryLib.encodeStablecoinCreateParams(name, symbol, initialAdmin, currency);
        assertEq(actual, expected, "encoded blob must match hand-encoded struct byte-for-byte");
    }
}
