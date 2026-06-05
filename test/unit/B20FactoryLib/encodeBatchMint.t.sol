// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibEncodeBatchMintTest is B20FactoryLibTest {
    /// @notice Verifies the encoded blob matches `abi.encodeCall(IB20Asset.batchMint, ...)`.
    /// @dev    Pins the selector on `IB20Asset` (not `IB20` — batchMint
    ///         is an asset-variant primitive) and the dynamic
    ///         parallel-array argument shape. Fuzz lengths cover both
    ///         arrays empty and arrays of varying length, including the
    ///         mismatched case (the token, not this encoder, validates
    ///         parity at runtime).
    function test_encodeBatchMint_success_matchesAbiEncodeCall(address[] memory recipients, uint256[] memory amounts)
        public
        pure
    {
        bytes memory expected = abi.encodeCall(IB20Asset.batchMint, (recipients, amounts));
        bytes memory actual = B20FactoryLib.encodeBatchMint(recipients, amounts);
        assertEq(actual, expected, "init-call must match abi.encodeCall(IB20Asset.batchMint, ...)");
    }
}
