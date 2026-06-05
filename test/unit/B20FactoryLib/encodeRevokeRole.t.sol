// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeRevokeRoleTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20.revokeRole, ...)`.
    /// @dev    Pins the (bytes32, address) argument order; same shape as
    ///         `grantRole` so a swap between the two encoders would be
    ///         caught here.
    function test_encodeRevokeRole_success_matchesAbiEncodeCall(bytes32 role, address account) public pure {
        bytes memory expected = abi.encodeCall(IB20.revokeRole, (role, account));
        bytes memory actual = B20FactoryLib.encodeRevokeRole(role, account);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20.revokeRole, ...)");
    }
}
