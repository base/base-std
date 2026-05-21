// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecurityRoleConstantsTest is B20SecurityTest {
    /// @notice Verifies SECURITY_OPERATOR_ROLE equals keccak256("SECURITY_OPERATOR_ROLE")
    /// @dev Wire-format invariant: the Rust precompile derives the same keccak; a value
    ///      drift would silently break operator role checks across implementations.
    function test_securityOperatorRole_success_matchesKeccak() public view {
        assertEq(
            security().SECURITY_OPERATOR_ROLE(),
            keccak256("SECURITY_OPERATOR_ROLE"),
            "SECURITY_OPERATOR_ROLE must equal keccak256(\"SECURITY_OPERATOR_ROLE\")"
        );
        assertEq(
            security().SECURITY_OPERATOR_ROLE(),
            SECURITY_OPERATOR_ROLE,
            "compile-time copy in B20SecurityTest must match the contract value"
        );
    }

    /// @notice Verifies BURN_FROM_ROLE equals keccak256("BURN_FROM_ROLE")
    /// @dev Same wire-format invariant for the corp-actions clawback role.
    function test_burnFromRole_success_matchesKeccak() public view {
        assertEq(
            security().BURN_FROM_ROLE(),
            keccak256("BURN_FROM_ROLE"),
            "BURN_FROM_ROLE must equal keccak256(\"BURN_FROM_ROLE\")"
        );
        assertEq(security().BURN_FROM_ROLE(), BURN_FROM_ROLE, "compile-time copy in B20SecurityTest must match");
    }

    /// @notice Verifies the two variant role identifiers are distinct
    /// @dev Sanity check: a collision would let a single role grant accidentally authorize both
    ///      operator and burn-from paths.
    function test_securityRoles_success_distinct() public view {
        assertTrue(
            security().SECURITY_OPERATOR_ROLE() != security().BURN_FROM_ROLE(),
            "operator and burn-from role identifiers must be distinct"
        );
    }
}
