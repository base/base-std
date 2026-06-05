// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeStablecoinEventParamsTest is B20FactoryLibTest {
    /// @notice Verifies the output decodes back to a `B20StablecoinEventParams`
    ///         with the caller's currency and the current event-encoding version byte.
    /// @dev    Round-trips through `abi.decode` to pin the wire format the
    ///         `B20Created` `variantEventParams` field carries for STABLECOIN. The
    ///         event-params version is independent of the create-params version,
    ///         so this test pins against `B20_STABLECOIN_EVENT_PARAMS_VERSION`
    ///         specifically (not `B20_STABLECOIN_CREATE_PARAMS_VERSION`).
    function test_encodeStablecoinEventParams_success_roundTripsThroughDecode(string memory currency) public pure {
        bytes memory blob = B20FactoryLib.encodeStablecoinEventParams(currency);
        IB20Factory.B20StablecoinEventParams memory decoded = abi.decode(blob, (IB20Factory.B20StablecoinEventParams));

        assertEq(
            decoded.version,
            B20FactoryLib.B20_STABLECOIN_EVENT_PARAMS_VERSION,
            "version byte must match library constant"
        );
        assertEq(decoded.currency, currency, "currency must round-trip");
    }

    /// @notice Verifies the encoded blob is byte-identical to a hand-encoded
    ///         `B20StablecoinEventParams` struct.
    /// @dev    Pins the encoding shape so future field reordering on the
    ///         struct is caught against an explicit reference.
    function test_encodeStablecoinEventParams_success_matchesHandEncodedStruct(string memory currency) public pure {
        bytes memory expected = abi.encode(
            IB20Factory.B20StablecoinEventParams({
                version: B20FactoryLib.B20_STABLECOIN_EVENT_PARAMS_VERSION, currency: currency
            })
        );
        bytes memory actual = B20FactoryLib.encodeStablecoinEventParams(currency);
        assertEq(actual, expected, "encoded blob must match hand-encoded struct byte-for-byte");
    }
}
