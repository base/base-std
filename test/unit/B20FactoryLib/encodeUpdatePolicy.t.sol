// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdatePolicyTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20.updatePolicy, ...)`.
    /// @dev    Pins both the selector and the (bytes32, uint64) argument
    ///         order. A swapped-arg regression would land scope bytes in
    ///         the policy-id slot and vice versa.
    function test_encodeUpdatePolicy_success_matchesAbiEncodeCall(bytes32 policyScope, uint64 newPolicyId) public pure {
        bytes memory expected = abi.encodeCall(IB20.updatePolicy, (policyScope, newPolicyId));
        bytes memory actual = B20FactoryLib.encodeUpdatePolicy(policyScope, newPolicyId);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20.updatePolicy, ...)");
    }
}
