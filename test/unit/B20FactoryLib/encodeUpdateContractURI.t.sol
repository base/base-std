// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdateContractURITest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20.updateContractURI, ...)`.
    /// @dev    Pins the selector binding and the single-string argument
    ///         shape across both short- and long-string fuzz inputs.
    function test_encodeUpdateContractURI_success_matchesAbiEncodeCall(string memory newURI) public pure {
        bytes memory expected = abi.encodeCall(IB20.updateContractURI, (newURI));
        bytes memory actual = B20FactoryLib.encodeUpdateContractURI(newURI);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20.updateContractURI, ...)");
    }
}
