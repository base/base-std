// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdateNameTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20.updateName, ...)`.
    /// @dev    Pins the selector binding and string-argument shape; both
    ///         the ERC-20 surface and the EIP-712 domain name depend on
    ///         this init call landing intact.
    function test_encodeUpdateName_success_matchesAbiEncodeCall(string memory newName) public pure {
        bytes memory expected = abi.encodeCall(IB20.updateName, (newName));
        bytes memory actual = B20FactoryLib.encodeUpdateName(newName);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20.updateName, ...)");
    }
}
