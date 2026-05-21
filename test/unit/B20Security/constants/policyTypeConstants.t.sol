// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecurityPolicyTypeConstantsTest is B20SecurityTest {
    /// @notice Verifies REDEEM_SENDER_POLICY equals keccak256("REDEEM_SENDER_POLICY")
    /// @dev Wire-format invariant: identifies the policy slot the redeem path consults
    ///      against msg.sender; a value drift would silently misroute the policy lookup.
    function test_redeemSenderPolicy_success_matchesKeccak() public view {
        assertEq(
            security().REDEEM_SENDER_POLICY(),
            keccak256("REDEEM_SENDER_POLICY"),
            "REDEEM_SENDER_POLICY must equal keccak256(\"REDEEM_SENDER_POLICY\")"
        );
        assertEq(
            security().REDEEM_SENDER_POLICY(),
            REDEEM_SENDER_POLICY,
            "compile-time copy in B20SecurityTest must match the contract value"
        );
    }
}
