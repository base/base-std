// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @notice Folds the four trivial policy-type constant readers
///         into one file since each is a one-stub assertion against a
///         fixed keccak digest. Substantive policy-related functions
///         (`policyId`, `updatePolicy`) live in their own files.
contract B20PolicyTypeConstantsTest is B20Test {
    /// @notice Verifies TRANSFER_SENDER_POLICY returns keccak256("TRANSFER_SENDER_POLICY")
    /// @dev Constant stability for off-chain consumers
    function test_TRANSFER_SENDER_POLICY_success_matchesExpected() public view {
        assertEq(
            token.TRANSFER_SENDER_POLICY(),
            keccak256("TRANSFER_SENDER_POLICY"),
            "B20Constants.TRANSFER_SENDER_POLICY digest"
        );
        assertEq(
            token.TRANSFER_SENDER_POLICY(), B20Constants.TRANSFER_SENDER_POLICY, "must match B20Test's local constant"
        );
    }

    /// @notice Verifies TRANSFER_RECEIVER_POLICY returns keccak256("TRANSFER_RECEIVER_POLICY")
    /// @dev Constant stability for off-chain consumers
    function test_TRANSFER_RECEIVER_POLICY_success_matchesExpected() public view {
        assertEq(
            token.TRANSFER_RECEIVER_POLICY(),
            keccak256("TRANSFER_RECEIVER_POLICY"),
            "B20Constants.TRANSFER_RECEIVER_POLICY digest"
        );
        assertEq(
            token.TRANSFER_RECEIVER_POLICY(),
            B20Constants.TRANSFER_RECEIVER_POLICY,
            "must match B20Test's local constant"
        );
    }

    /// @notice Verifies TRANSFER_EXECUTOR_POLICY returns keccak256("TRANSFER_EXECUTOR_POLICY")
    /// @dev Constant stability for off-chain consumers
    function test_TRANSFER_EXECUTOR_POLICY_success_matchesExpected() public view {
        assertEq(
            token.TRANSFER_EXECUTOR_POLICY(),
            keccak256("TRANSFER_EXECUTOR_POLICY"),
            "B20Constants.TRANSFER_EXECUTOR_POLICY digest"
        );
        assertEq(
            token.TRANSFER_EXECUTOR_POLICY(),
            B20Constants.TRANSFER_EXECUTOR_POLICY,
            "must match B20Test's local constant"
        );
    }

    /// @notice Verifies MINT_RECEIVER_POLICY returns keccak256("MINT_RECEIVER_POLICY")
    /// @dev Constant stability for off-chain consumers
    function test_MINT_RECEIVER_POLICY_success_matchesExpected() public view {
        assertEq(
            token.MINT_RECEIVER_POLICY(), keccak256("MINT_RECEIVER_POLICY"), "B20Constants.MINT_RECEIVER_POLICY digest"
        );
        assertEq(token.MINT_RECEIVER_POLICY(), B20Constants.MINT_RECEIVER_POLICY, "must match B20Test's local constant");
    }
}
