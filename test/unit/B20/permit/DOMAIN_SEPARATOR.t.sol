// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20DomainSeparatorTest is B20Test {
    /// @notice Verifies DOMAIN_SEPARATOR matches the EIP-712 hash of the eip712Domain fields
    /// @dev Cross-check: separator must equal keccak256(abi.encode(typeHash, ...domain fields))
    function test_DOMAIN_SEPARATOR_success_matchesDomainFields() public {
        // unimplemented
    }

    /// @notice Verifies DOMAIN_SEPARATOR is recomputed when block.chainid changes
    /// @dev Fork-safety: separator depends on chainId so post-fork signatures don't replay
    function test_DOMAIN_SEPARATOR_success_changesAfterChainIdFork(uint256 newChainId) public {
        // unimplemented
    }
}
