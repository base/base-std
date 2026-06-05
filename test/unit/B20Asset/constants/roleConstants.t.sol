// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetRoleConstantsTest is B20AssetTest {
    /// @notice Verifies OPERATOR_ROLE equals keccak256("OPERATOR_ROLE")
    /// @dev Wire-format invariant: the Rust precompile derives the same keccak; a value
    ///      drift would silently break operator role checks across implementations.
    function test_operatorRole_success_matchesKeccak() public view {
        assertEq(
            asset().OPERATOR_ROLE(), keccak256("OPERATOR_ROLE"), "OPERATOR_ROLE must equal keccak256(\"OPERATOR_ROLE\")"
        );
        assertEq(
            asset().OPERATOR_ROLE(), OPERATOR_ROLE, "compile-time copy in B20AssetTest must match the contract value"
        );
        assertEq(
            asset().OPERATOR_ROLE(),
            B20Constants.OPERATOR_ROLE,
            "B20Constants.OPERATOR_ROLE library source-of-truth must match"
        );
    }
}
