// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecurityRoleConstantsTest is B20SecurityTest {
    /// @notice Verifies OPERATOR_ROLE equals keccak256("OPERATOR_ROLE")
    /// @dev Wire-format invariant: the Rust precompile derives the same keccak; a value
    ///      drift would silently break operator role checks across implementations.
    function test_operatorRole_success_matchesKeccak() public view {
        assertEq(
            security().OPERATOR_ROLE(),
            keccak256("OPERATOR_ROLE"),
            "OPERATOR_ROLE must equal keccak256(\"OPERATOR_ROLE\")"
        );
        assertEq(
            security().OPERATOR_ROLE(),
            OPERATOR_ROLE,
            "compile-time copy in B20SecurityTest must match the contract value"
        );
        assertEq(
            security().OPERATOR_ROLE(),
            B20Constants.OPERATOR_ROLE,
            "B20Constants.OPERATOR_ROLE library source-of-truth must match"
        );
    }
}
