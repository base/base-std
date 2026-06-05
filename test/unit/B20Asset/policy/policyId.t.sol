// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";

contract B20AssetPolicyIdTest is B20AssetTest {
    /// @notice Verifies policyId still resolves the four base policy types on the asset variant.
    /// @dev The asset variant's `policyId` resolution path must still terminate in the base
    ///      implementation for the four canonical scopes; a fresh token reports the EVM zero
    ///      default (`ALWAYS_ALLOW`) for each.
    function test_policyId_success_baseTypesStillResolve() public view {
        // All four base types default to 0 (ALWAYS_ALLOW) on a fresh token.
        assertEq(token.policyId(B20Constants.TRANSFER_SENDER_POLICY), uint64(0), "TRANSFER_SENDER must resolve");
        assertEq(token.policyId(B20Constants.TRANSFER_RECEIVER_POLICY), uint64(0), "TRANSFER_RECEIVER must resolve");
        assertEq(token.policyId(B20Constants.TRANSFER_EXECUTOR_POLICY), uint64(0), "TRANSFER_EXECUTOR must resolve");
        assertEq(token.policyId(B20Constants.MINT_RECEIVER_POLICY), uint64(0), "MINT_RECEIVER must resolve");
    }
}
