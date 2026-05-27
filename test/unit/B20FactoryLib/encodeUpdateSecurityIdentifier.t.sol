// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "src/lib/B20FactoryLib.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {B20FactoryLibTest} from "test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdateSecurityIdentifierTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches
    ///         `abi.encodeCall(IB20Security.updateSecurityIdentifier, ...)`.
    /// @dev    Pins the selector binding on `IB20Security` and the
    ///         (string, string) argument order across short- and
    ///         long-string fuzz inputs.
    function test_encodeUpdateSecurityIdentifier_success_matchesAbiEncodeCall(
        string memory identifierType,
        string memory value
    ) public pure {
        bytes memory expected = abi.encodeCall(IB20Security.updateSecurityIdentifier, (identifierType, value));
        bytes memory actual = B20FactoryLib.encodeUpdateSecurityIdentifier(identifierType, value);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20Security.updateSecurityIdentifier, ...)");
    }
}
