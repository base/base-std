// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {B20Constants} from "src/lib/B20Constants.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20SecurityPolicyIdTest is B20SecurityTest {
    /// @notice Verifies policyId(REDEEM_SENDER_POLICY) returns ALWAYS_BLOCK_ID on a fresh token.
    /// @dev The factory seeds the redeemPolicyIds lane with ALWAYS_BLOCK_ID at creation so
    ///      redemption is closed by default. Issuers must explicitly open it via updatePolicy.
    function test_policyId_success_redeemSenderDefaultIsAlwaysBlock() public view {
        assertEq(
            token.policyId(REDEEM_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "default REDEEM_SENDER_POLICY id must be ALWAYS_BLOCK_ID"
        );
    }

    /// @notice Verifies policyId(REDEEM_SENDER_POLICY) reads back the last write
    /// @dev Round-trip through the variant override. Built-in sentinels avoid needing registry setup.
    function test_policyId_success_redeemSenderReturnsWrittenValue() public {
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        assertEq(
            token.policyId(REDEEM_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "REDEEM_SENDER_POLICY must read back ALWAYS_ALLOW_ID"
        );
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(
            token.policyId(REDEEM_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "REDEEM_SENDER_POLICY must read back ALWAYS_BLOCK_ID"
        );
    }

    /// @notice Verifies policyId still resolves the four base policy types after the override
    /// @dev The variant's `_readPolicyId` checks REDEEM_SENDER_POLICY first then `super`s to
    ///      the base; this confirms the super-fallthrough still works for base types.
    function test_policyId_success_baseTypesStillResolve() public view {
        // All four base types default to 0 (ALWAYS_ALLOW) on a fresh token.
        assertEq(token.policyId(B20Constants.TRANSFER_SENDER_POLICY), uint64(0), "TRANSFER_SENDER must resolve");
        assertEq(token.policyId(B20Constants.TRANSFER_RECEIVER_POLICY), uint64(0), "TRANSFER_RECEIVER must resolve");
        assertEq(token.policyId(B20Constants.TRANSFER_EXECUTOR_POLICY), uint64(0), "TRANSFER_EXECUTOR must resolve");
        assertEq(token.policyId(B20Constants.MINT_RECEIVER_POLICY), uint64(0), "MINT_RECEIVER must resolve");
    }
}
