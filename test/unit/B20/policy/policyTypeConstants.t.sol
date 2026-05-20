// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

/// @notice Folds the four trivial policy-type identifier constant readers
///         into one file since each is a one-stub assertion against a
///         fixed keccak digest. Substantive policy-related functions
///         (`policyId`, `updatePolicy`) live in their own files.
contract B20PolicyTypeConstantsTest is B20Test {
    /// @notice Verifies TRANSFER_SENDER returns keccak256("TRANSFER_SENDER")
    /// @dev Identifier stability for off-chain consumers
    function test_TRANSFER_SENDER_success_matchesExpected() public view {
        assertEq(token.TRANSFER_SENDER(), keccak256("TRANSFER_SENDER"), "B20Constants.TRANSFER_SENDER digest");
        assertEq(token.TRANSFER_SENDER(), B20Constants.TRANSFER_SENDER, "must match B20Test's local constant");
    }

    /// @notice Verifies TRANSFER_RECEIVER returns keccak256("TRANSFER_RECEIVER")
    /// @dev Identifier stability for off-chain consumers
    function test_TRANSFER_RECEIVER_success_matchesExpected() public view {
        assertEq(token.TRANSFER_RECEIVER(), keccak256("TRANSFER_RECEIVER"), "B20Constants.TRANSFER_RECEIVER digest");
        assertEq(token.TRANSFER_RECEIVER(), B20Constants.TRANSFER_RECEIVER, "must match B20Test's local constant");
    }

    /// @notice Verifies TRANSFER_EXECUTOR returns keccak256("TRANSFER_EXECUTOR")
    /// @dev Identifier stability for off-chain consumers
    function test_TRANSFER_EXECUTOR_success_matchesExpected() public view {
        assertEq(token.TRANSFER_EXECUTOR(), keccak256("TRANSFER_EXECUTOR"), "B20Constants.TRANSFER_EXECUTOR digest");
        assertEq(token.TRANSFER_EXECUTOR(), B20Constants.TRANSFER_EXECUTOR, "must match B20Test's local constant");
    }

    /// @notice Verifies MINT_RECEIVER returns keccak256("MINT_RECEIVER")
    /// @dev Identifier stability for off-chain consumers
    function test_MINT_RECEIVER_success_matchesExpected() public view {
        assertEq(token.MINT_RECEIVER(), keccak256("MINT_RECEIVER"), "B20Constants.MINT_RECEIVER digest");
        assertEq(token.MINT_RECEIVER(), B20Constants.MINT_RECEIVER, "must match B20Test's local constant");
    }
}
