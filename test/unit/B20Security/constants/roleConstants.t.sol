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
}
