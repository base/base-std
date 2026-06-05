// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeUpdateMultiplierTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20Asset.updateMultiplier, ...)`.
    /// @dev    Pins the selector binding and uint argument shape for the bootstrap multiplier
    ///         init call. The asset variant's scaled-balance reads all derive from the
    ///         multiplier this call seeds, so a selector/arg drift would silently mis-scale balances.
    function test_encodeUpdateMultiplier_success_matchesAbiEncodeCall(uint256 newMultiplier) public pure {
        bytes memory expected = abi.encodeCall(IB20Asset.updateMultiplier, (newMultiplier));
        bytes memory actual = B20FactoryLib.encodeUpdateMultiplier(newMultiplier);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20Asset.updateMultiplier, ...)");
    }
}
