// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdateExtraMetadataTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches
    ///         `abi.encodeCall(IB20Asset.updateExtraMetadata, ...)`.
    /// @dev    Pins the selector binding on `IB20Asset` and the
    ///         (string, string) argument order across short- and
    ///         long-string fuzz inputs.
    function test_encodeUpdateExtraMetadata_success_matchesAbiEncodeCall(string memory key, string memory value)
        public
        pure
    {
        bytes memory expected = abi.encodeCall(IB20Asset.updateExtraMetadata, (key, value));
        bytes memory actual = B20FactoryLib.encodeUpdateExtraMetadata(key, value);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20Asset.updateExtraMetadata, ...)");
    }
}
