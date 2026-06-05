// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdateSupplyCapTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20.updateSupplyCap, ...)`.
    /// @dev    Pins the selector binding to `IB20.updateSupplyCap` and the
    ///         single-argument shape. A drifted argument order or wrong
    ///         selector would produce a different byte string.
    function test_encodeUpdateSupplyCap_success_matchesAbiEncodeCall(uint256 newSupplyCap) public pure {
        bytes memory expected = abi.encodeCall(IB20.updateSupplyCap, (newSupplyCap));
        bytes memory actual = B20FactoryLib.encodeUpdateSupplyCap(newSupplyCap);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20.updateSupplyCap, ...)");
    }
}
