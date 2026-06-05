// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @notice Folds the seven trivial role-constant readers into one
///         file since each is a one-stub assertion against a fixed keccak
///         digest. Substantive role-related functions (`grantRole`,
///         `revokeRole`, etc.) live in their own files.
contract B20RoleConstantsTest is B20Test {
    /// @notice Verifies DEFAULT_ADMIN_ROLE returns the OZ AccessControl default value (bytes32(0))
    /// @dev Matches OZ's `DEFAULT_ADMIN_ROLE = 0x00` convention
    function test_DEFAULT_ADMIN_ROLE_success_matchesExpected() public view {
        assertEq(token.DEFAULT_ADMIN_ROLE(), bytes32(0), "B20Constants.DEFAULT_ADMIN_ROLE must be bytes32(0)");
        // And matches the local constant used across these tests.
        assertEq(token.DEFAULT_ADMIN_ROLE(), B20Constants.DEFAULT_ADMIN_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies MINT_ROLE returns keccak256("MINT_ROLE")
    /// @dev Constant stability for off-chain consumers
    function test_MINT_ROLE_success_matchesExpected() public view {
        assertEq(token.MINT_ROLE(), keccak256("MINT_ROLE"), "B20Constants.MINT_ROLE digest");
        assertEq(token.MINT_ROLE(), B20Constants.MINT_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies BURN_ROLE returns keccak256("BURN_ROLE")
    /// @dev Constant stability for off-chain consumers
    function test_BURN_ROLE_success_matchesExpected() public view {
        assertEq(token.BURN_ROLE(), keccak256("BURN_ROLE"), "B20Constants.BURN_ROLE digest");
        assertEq(token.BURN_ROLE(), B20Constants.BURN_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies BURN_BLOCKED_ROLE returns keccak256("BURN_BLOCKED_ROLE")
    /// @dev Constant stability for off-chain consumers
    function test_BURN_BLOCKED_ROLE_success_matchesExpected() public view {
        assertEq(token.BURN_BLOCKED_ROLE(), keccak256("BURN_BLOCKED_ROLE"), "B20Constants.BURN_BLOCKED_ROLE digest");
        assertEq(token.BURN_BLOCKED_ROLE(), B20Constants.BURN_BLOCKED_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies PAUSE_ROLE returns keccak256("PAUSE_ROLE")
    /// @dev Constant stability for off-chain consumers
    function test_PAUSE_ROLE_success_matchesExpected() public view {
        assertEq(token.PAUSE_ROLE(), keccak256("PAUSE_ROLE"), "B20Constants.PAUSE_ROLE digest");
        assertEq(token.PAUSE_ROLE(), B20Constants.PAUSE_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies UNPAUSE_ROLE returns keccak256("UNPAUSE_ROLE")
    /// @dev Constant stability for off-chain consumers
    function test_UNPAUSE_ROLE_success_matchesExpected() public view {
        assertEq(token.UNPAUSE_ROLE(), keccak256("UNPAUSE_ROLE"), "B20Constants.UNPAUSE_ROLE digest");
        assertEq(token.UNPAUSE_ROLE(), B20Constants.UNPAUSE_ROLE, "must match B20Test's local constant");
    }

    /// @notice Verifies METADATA_ROLE returns keccak256("METADATA_ROLE")
    /// @dev Constant stability for off-chain consumers. METADATA_ROLE gates `updateName`
    ///      and `updateSymbol` (separated from DEFAULT_ADMIN_ROLE per IB20 spec).
    function test_METADATA_ROLE_success_matchesExpected() public view {
        assertEq(token.METADATA_ROLE(), keccak256("METADATA_ROLE"), "B20Constants.METADATA_ROLE digest");
        assertEq(token.METADATA_ROLE(), B20Constants.METADATA_ROLE, "must match B20Test's local constant");
    }
}
