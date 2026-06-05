// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {MockActivationRegistryStorage} from "base-std-test/lib/mocks/MockActivationRegistryStorage.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Asserts the hardcoded `STORAGE_LOCATION` constant on
///         `MockActivationRegistryStorage` matches the ERC-7201 formula it documents.
///
/// This constant is the storage-layout contract between the Solidity mock and
/// the Rust precompile impl: both sides hash the same namespace string and
/// arrive at the same root slot. Verifying the constant against the formula
/// in-tree ensures a stale `STORAGE_LOCATION` literal can't drift silently
/// when the namespace changes.
contract MockActivationRegistryStorageLocationTest is Test {
    /// @notice `MockActivationRegistryStorage.STORAGE_LOCATION` equals
    ///         keccak256(abi.encode(uint256(keccak256("base.activation_registry")) - 1)) & ~bytes32(uint256(0xff)).
    function test_MockActivationRegistryStorage_storageLocation_matchesFormula() public pure {
        assertEq(
            MockActivationRegistryStorage.STORAGE_LOCATION,
            MockActivationRegistryStorage.derivedLocation(),
            "MockActivationRegistryStorage.STORAGE_LOCATION must match its ERC-7201 derivation"
        );
    }

    /// @notice The activation-registry namespace must not collide with `base.b20`.
    /// @dev Sanity check: different precompiles must have disjoint storage roots.
    function test_MockActivationRegistryStorage_storageLocation_disjointFromB20() public pure {
        assertTrue(
            MockActivationRegistryStorage.STORAGE_LOCATION != MockB20Storage.derivedLocation(),
            "activation_registry and b20 namespaces must derive to disjoint roots"
        );
    }

    /// @notice The activation-registry namespace must not collide with `base.policy_registry`.
    /// @dev Sanity check: different precompiles must have disjoint storage roots.
    function test_MockActivationRegistryStorage_storageLocation_disjointFromPolicyRegistry() public pure {
        assertTrue(
            MockActivationRegistryStorage.STORAGE_LOCATION != MockPolicyRegistryStorage.derivedLocation(),
            "activation_registry and policy_registry namespaces must derive to disjoint roots"
        );
    }
}
