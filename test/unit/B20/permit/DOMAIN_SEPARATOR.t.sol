// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20DomainSeparatorTest is B20Test {
    /// @dev Canonical EIP-2612 domain type hash, recomputed in-test from the
    ///      exact string the IB20 spec pins so this assertion catches drift
    ///      between the contract's constant and the documented shape.
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev Pre-hashed version field. IB20 fixes `version = "1"` and bumping
    ///      it requires a new contract, so the constant is hardcoded here
    ///      rather than read from the token.
    bytes32 internal constant VERSION_HASH = keccak256(bytes("1"));

    /// @notice Verifies DOMAIN_SEPARATOR matches the EIP-712 hash of the (name, version, chainId, verifyingContract) tuple
    /// @dev Cross-check: separator must equal keccak256(abi.encode(typeHash, keccak256(name), keccak256("1"), chainId, verifyingContract))
    function test_DOMAIN_SEPARATOR_success_matchesDomainFields() public view {
        bytes32 expected = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(token.name())), VERSION_HASH, block.chainid, address(token))
        );
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
        bytes32 expected = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(token.name())), VERSION_HASH, newChainId, address(token))
        );
        assertEq(afterFork, expected, "post-fork separator must match new chainId");
    }

    /// @notice Verifies DOMAIN_SEPARATOR is recomputed when name changes via updateName
    /// @dev Signature-invalidation: name participates in the domain hash, so a successful
    ///      updateName must move the separator off its previous value. This is the property
    ///      that invalidates outstanding permit signatures issued under the previous name.
    function test_DOMAIN_SEPARATOR_success_changesAfterUpdateName(string calldata newName) public {
        vm.assume(keccak256(bytes(newName)) != keccak256(bytes(token.name())));

        bytes32 before = token.DOMAIN_SEPARATOR();
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateName(newName);
        bytes32 afterRename = token.DOMAIN_SEPARATOR();

        assertTrue(before != afterRename, "separator must change with name");
    }

    /// @notice Verifies DOMAIN_SEPARATOR matches the recomputed value after updateName
    /// @dev Stronger form of the changesAfterUpdateName test: the post-rename separator
    ///      must equal the expected hash computed with the new name, not just "some
    ///      different value". Catches a class of bugs where updateName mutates the slot
    ///      but the separator computation reads from a cached / wrong slot.
    function test_DOMAIN_SEPARATOR_success_matchesAfterUpdateName(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateName(newName);

        bytes32 expected = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(newName)), VERSION_HASH, block.chainid, address(token))
        );
        assertEq(token.DOMAIN_SEPARATOR(), expected, "separator must match value computed with new name");
    }
}
