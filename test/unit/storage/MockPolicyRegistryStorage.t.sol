// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Asserts the hardcoded `STORAGE_LOCATION` constant on
///         `MockPolicyRegistryStorage` matches the ERC-7201 formula it documents.
///
/// This constant is the storage-layout contract between the Solidity mock and
/// the Rust precompile impl: both sides hash the same namespace string and
/// arrive at the same root slot. Verifying the constant against the formula
/// in-tree ensures a stale `STORAGE_LOCATION` literal can't drift silently
/// when the namespace changes.
contract MockPolicyRegistryStorageLocationTest is Test {
    /// @notice `MockPolicyRegistryStorage.STORAGE_LOCATION` equals
    ///         keccak256(abi.encode(uint256(keccak256("base.policy_registry")) - 1)) & ~bytes32(uint256(0xff)).
    function test_MockPolicyRegistryStorage_storageLocation_matchesFormula() public pure {
        assertEq(
            MockPolicyRegistryStorage.STORAGE_LOCATION,
            MockPolicyRegistryStorage.derivedLocation(),
            "MockPolicyRegistryStorage.STORAGE_LOCATION must match its ERC-7201 derivation"
        );
    }

    /// @notice The policy-registry namespace must not collide with `base.b20`.
    /// @dev Sanity check: different precompiles must have disjoint storage roots.
    function test_MockPolicyRegistryStorage_storageLocation_disjointFromB20() public pure {
        assertTrue(
            MockPolicyRegistryStorage.STORAGE_LOCATION != MockB20Storage.derivedLocation(),
            "policy_registry and b20 namespaces must derive to disjoint roots"
        );
    }
}
