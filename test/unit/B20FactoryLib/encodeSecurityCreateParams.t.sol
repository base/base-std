// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "src/lib/B20FactoryLib.sol";
import {IB20Factory} from "src/interfaces/IB20Factory.sol";

import {B20FactoryLibTest} from "test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeSecurityCreateParamsTest is B20FactoryLibTest {
    /// @notice Verifies the output decodes back to a `B20SecurityCreateParams`
    ///         with the caller's fields and the current version byte.
    /// @dev    Round-trips through `abi.decode` to pin the wire format the
    ///         factory's security decode arm consumes (isin and
    ///         minimumRedeemable live on this struct).
    function test_encodeSecurityCreateParams_success_roundTripsThroughDecode(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory isin,
        uint256 minimumRedeemable
    ) public pure {
        bytes memory blob =
            B20FactoryLib.encodeSecurityCreateParams(name, symbol, initialAdmin, isin, minimumRedeemable);
        IB20Factory.B20SecurityCreateParams memory decoded =
            abi.decode(blob, (IB20Factory.B20SecurityCreateParams));

        assertEq(
            decoded.version,
            B20FactoryLib.B20_SECURITY_CREATE_PARAMS_VERSION,
            "version byte must match library constant"
        );
        assertEq(decoded.name, name, "name must round-trip");
        assertEq(decoded.symbol, symbol, "symbol must round-trip");
        assertEq(decoded.initialAdmin, initialAdmin, "initialAdmin must round-trip");
        assertEq(decoded.isin, isin, "isin must round-trip");
        assertEq(decoded.minimumRedeemable, minimumRedeemable, "minimumRedeemable must round-trip");
    }

    /// @notice Verifies the encoded blob is byte-identical to a hand-encoded
    ///         `B20SecurityCreateParams` struct.
    /// @dev    Pins the encoding shape so future field reordering on the
    ///         struct is caught against an explicit reference.
    function test_encodeSecurityCreateParams_success_matchesHandEncodedStruct(
        string memory name,
        string memory symbol,
        address initialAdmin,
        string memory isin,
        uint256 minimumRedeemable
    ) public pure {
        bytes memory expected = abi.encode(
            IB20Factory.B20SecurityCreateParams({
                version: B20FactoryLib.B20_SECURITY_CREATE_PARAMS_VERSION,
                name: name,
                symbol: symbol,
                initialAdmin: initialAdmin,
                isin: isin,
                minimumRedeemable: minimumRedeemable
            })
        );
        bytes memory actual =
            B20FactoryLib.encodeSecurityCreateParams(name, symbol, initialAdmin, isin, minimumRedeemable);
        assertEq(actual, expected, "encoded blob must match hand-encoded struct byte-for-byte");
    }
}
