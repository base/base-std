// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeSetRoleAdminTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20.setRoleAdmin, ...)`.
    /// @dev    Both arguments are `bytes32`, so a swapped argument order
    ///         would be byte-indistinguishable in the encoding layer —
    ///         this test pins it down via the typed `abi.encodeCall`
    ///         reference, which carries the function-type metadata.
    function test_encodeSetRoleAdmin_success_matchesAbiEncodeCall(bytes32 role, bytes32 newAdminRole) public pure {
        bytes memory expected = abi.encodeCall(IB20.setRoleAdmin, (role, newAdminRole));
        bytes memory actual = B20FactoryLib.encodeSetRoleAdmin(role, newAdminRole);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20.setRoleAdmin, ...)");
    }
}
