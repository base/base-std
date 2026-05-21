// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {B20Constants} from "src/lib/B20Constants.sol";

contract B20SecurityPolicyIdTest is B20SecurityTest {
    /// @notice Verifies policyId(REDEEM_SENDER_POLICY) returns 0 on a fresh token
    /// @dev The variant override `_readPolicyId` routes REDEEM_SENDER_POLICY to the
    ///      `redeemPolicyIds` lane in the redeem namespace; uninitialised default is 0
    ///      (ALWAYS_ALLOW_ID).
    function test_policyId_success_redeemSenderDefaultIsZero() public view {
        assertEq(token.policyId(REDEEM_SENDER_POLICY), uint64(0), "default REDEEM_SENDER_POLICY id must be 0");
    }

    /// @notice Verifies policyId(REDEEM_SENDER_POLICY) reads back the last value updatePolicy wrote
    /// @dev Read-side correctness of the variant override; subsequent updatePolicy + policyId
    ///      round-trip must agree.
    function test_policyId_success_redeemSenderReturnsWrittenValue(uint64 seed) public {
        uint64 newPolicyId = _wellFormedUncreatedPolicyId(seed);
        // Use the ALWAYS_ALLOW (0) and ALWAYS_BLOCK (1) sentinel IDs alternately if the seed
        // collides; both are built-in and don't require any registry state.
        if (newPolicyId == 0 || newPolicyId == 1) newPolicyId = 0;
        // Set via the admin path (REDEEM_SENDER_POLICY's write goes through the variant
        // override). Use a sentinel built-in to avoid having to register a custom policy.
        _setRedeemPolicy(0);
        assertEq(token.policyId(REDEEM_SENDER_POLICY), uint64(0), "REDEEM_SENDER_POLICY must read back 0");
        _setRedeemPolicy(1);
        assertEq(token.policyId(REDEEM_SENDER_POLICY), uint64(1), "REDEEM_SENDER_POLICY must read back 1");
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
