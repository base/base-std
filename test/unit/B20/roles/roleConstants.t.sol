// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

/// @notice Folds the six trivial role-identifier constant readers into one
///         file since each is a one-stub assertion against a fixed keccak
///         digest. Substantive role-related functions (`grantRole`,
///         `revokeRole`, etc.) live in their own files.
contract B20RoleConstantsTest is B20Test {
    /// @notice Verifies DEFAULT_ADMIN_ROLE returns the OZ AccessControl default value (bytes32(0))
    /// @dev Matches OZ's `DEFAULT_ADMIN_ROLE = 0x00` convention
    function test_DEFAULT_ADMIN_ROLE_success_matchesExpected() public view {
        assertEq(token.DEFAULT_ADMIN_ROLE(), bytes32(0), "DEFAULT_ADMIN_ROLE must be bytes32(0)");
        // And matches the local constant used across these tests.
        assertEq(token.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies MINT_ROLE returns keccak256("MINT_ROLE")
    /// @dev Identifier stability for off-chain consumers
    function test_MINT_ROLE_success_matchesExpected() public view {
        assertEq(token.MINT_ROLE(), keccak256("MINT_ROLE"), "MINT_ROLE digest");
        assertEq(token.MINT_ROLE(), MINT_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies BURN_ROLE returns keccak256("BURN_ROLE")
    /// @dev Identifier stability for off-chain consumers
    function test_BURN_ROLE_success_matchesExpected() public view {
        assertEq(token.BURN_ROLE(), keccak256("BURN_ROLE"), "BURN_ROLE digest");
        assertEq(token.BURN_ROLE(), BURN_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies BURN_BLOCKED_ROLE returns keccak256("BURN_BLOCKED_ROLE")
    /// @dev Identifier stability for off-chain consumers
    function test_BURN_BLOCKED_ROLE_success_matchesExpected() public view {
        assertEq(token.BURN_BLOCKED_ROLE(), keccak256("BURN_BLOCKED_ROLE"), "BURN_BLOCKED_ROLE digest");
        assertEq(token.BURN_BLOCKED_ROLE(), BURN_BLOCKED_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies PAUSE_ROLE returns keccak256("PAUSE_ROLE")
    /// @dev Identifier stability for off-chain consumers
    function test_PAUSE_ROLE_success_matchesExpected() public view {
        assertEq(token.PAUSE_ROLE(), keccak256("PAUSE_ROLE"), "PAUSE_ROLE digest");
        assertEq(token.PAUSE_ROLE(), PAUSE_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies UNPAUSE_ROLE returns keccak256("UNPAUSE_ROLE")
    /// @dev Identifier stability for off-chain consumers
    function test_UNPAUSE_ROLE_success_matchesExpected() public view {
        assertEq(token.UNPAUSE_ROLE(), keccak256("UNPAUSE_ROLE"), "UNPAUSE_ROLE digest");
        assertEq(token.UNPAUSE_ROLE(), UNPAUSE_ROLE, "must match B20Test's local constant");
    }
}
