// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20DomainSeparatorTest is B20Test {
    // EIP-712 domain type hash for the (chainId, verifyingContract)-only shape.
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /// @notice Verifies DOMAIN_SEPARATOR matches the EIP-712 hash of the eip712Domain fields
    /// @dev Cross-check: separator must equal keccak256(abi.encode(typeHash, chainId, verifyingContract))
    function test_DOMAIN_SEPARATOR_success_matchesDomainFields() public view {
        bytes32 expected = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(token)));
        assertEq(token.DOMAIN_SEPARATOR(), expected, "separator must match computed value");
    }

    /// @notice Verifies DOMAIN_SEPARATOR is recomputed when block.chainid changes
    /// @dev Fork-safety: separator depends on chainId so post-fork signatures don't replay
    function test_DOMAIN_SEPARATOR_success_changesAfterChainIdFork(uint256 newChainId) public {
        // vm.chainId requires uint64 range.
        newChainId = bound(newChainId, 1, type(uint64).max);
        vm.assume(newChainId != block.chainid);

        bytes32 before = token.DOMAIN_SEPARATOR();
        vm.chainId(newChainId);
        bytes32 afterFork = token.DOMAIN_SEPARATOR();

        assertTrue(before != afterFork, "separator must change with chainId");
        bytes32 expected = keccak256(abi.encode(DOMAIN_TYPEHASH, newChainId, address(token)));
        assertEq(afterFork, expected, "post-fork separator must match new chainId");
    }
}
