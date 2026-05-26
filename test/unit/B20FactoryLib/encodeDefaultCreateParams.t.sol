// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "src/lib/B20FactoryLib.sol";
import {IB20Factory} from "src/interfaces/IB20Factory.sol";

import {B20FactoryLibTest} from "test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeDefaultCreateParamsTest is B20FactoryLibTest {
    /// @notice Verifies the output decodes back to a `B20CreateParams` with the
    ///         caller's fields and the current version byte.
    /// @dev    Round-trips the blob through `abi.decode` to pin the wire format
    ///         the factory's decode side consumes.
    function test_encodeDefaultCreateParams_success_roundTripsThroughDecode(
        string memory name,
        string memory symbol,
        address initialAdmin
    ) public pure {
        bytes memory blob = B20FactoryLib.encodeDefaultCreateParams(name, symbol, initialAdmin);
        IB20Factory.B20CreateParams memory decoded = abi.decode(blob, (IB20Factory.B20CreateParams));

        assertEq(decoded.version, B20FactoryLib.B20_CREATE_PARAMS_VERSION, "version byte must match library constant");
        assertEq(decoded.name, name, "name must round-trip");
        assertEq(decoded.symbol, symbol, "symbol must round-trip");
        assertEq(decoded.initialAdmin, initialAdmin, "initialAdmin must round-trip");
    }

    /// @notice Verifies the encoded blob is byte-identical to a hand-encoded
    ///         `B20CreateParams` struct.
    /// @dev    Pins the encoding shape: a buggy edit that, say, drops the
    ///         version field would change the byte layout and a decode-only
    ///         round-trip might still pass under a compatible re-shuffle.
    function test_encodeDefaultCreateParams_success_matchesHandEncodedStruct(
        string memory name,
        string memory symbol,
        address initialAdmin
    ) public pure {
        bytes memory expected = abi.encode(
            IB20Factory.B20CreateParams({
                version: B20FactoryLib.B20_CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin
            })
        );
        bytes memory actual = B20FactoryLib.encodeDefaultCreateParams(name, symbol, initialAdmin);
        assertEq(actual, expected, "encoded blob must match hand-encoded struct byte-for-byte");
    }
}
