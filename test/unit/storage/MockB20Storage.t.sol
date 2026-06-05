// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {
    MockB20Storage,
    MockB20StablecoinStorage,
    MockB20AssetStorage
} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @notice Asserts the hardcoded `STORAGE_LOCATION` constants on the B-20
///         storage libraries match the ERC-7201 formula they document.
///
/// These constants are the storage-layout contract between the Solidity
/// mocks and the Rust precompile impl: both sides hash the same namespace
/// string and arrive at the same root slot. Verifying the constant against
/// the formula in-tree ensures a stale `STORAGE_LOCATION` literal can't
/// drift silently when the namespace changes.
contract MockB20StorageLocationTest is Test {
    /// @notice `MockB20Storage.STORAGE_LOCATION` equals
    ///         keccak256(abi.encode(uint256(keccak256("base.b20")) - 1)) & ~bytes32(uint256(0xff)).
    function test_MockB20Storage_storageLocation_matchesFormula() public pure {
        assertEq(
            MockB20Storage.STORAGE_LOCATION,
            MockB20Storage.derivedLocation(),
            "MockB20Storage.STORAGE_LOCATION must match its ERC-7201 derivation"
        );
    }

    /// @notice `MockB20StablecoinStorage.STORAGE_LOCATION` equals
    ///         keccak256(abi.encode(uint256(keccak256("base.b20.stablecoin")) - 1)) & ~bytes32(uint256(0xff)).
    function test_MockB20StablecoinStorage_storageLocation_matchesFormula() public pure {
        assertEq(
            MockB20StablecoinStorage.STORAGE_LOCATION,
            MockB20StablecoinStorage.derivedLocation(),
            "MockB20StablecoinStorage.STORAGE_LOCATION must match its ERC-7201 derivation"
        );
    }

    /// @notice `MockB20AssetStorage.STORAGE_LOCATION` equals
    ///         keccak256(abi.encode(uint256(keccak256("base.b20.asset")) - 1)) & ~bytes32(uint256(0xff)).
    function test_MockB20AssetStorage_storageLocation_matchesFormula() public pure {
        assertEq(
            MockB20AssetStorage.STORAGE_LOCATION,
            MockB20AssetStorage.derivedLocation(),
            "MockB20AssetStorage.STORAGE_LOCATION must match its ERC-7201 derivation"
        );
    }

    /// @notice Every B-20 namespace must derive to a distinct storage root.
    /// @dev    All three libraries (base + two variant namespaces) compose
    ///         into a single B-20 token's storage, so any pair colliding
    ///         would silently overwrite fields. Tests `n*(n-1)/2` pairs
    ///         explicitly so the assertion message identifies which pair
    ///         drifted.
    function test_storageLocations_disjoint() public pure {
        assertTrue(
            MockB20Storage.STORAGE_LOCATION != MockB20StablecoinStorage.STORAGE_LOCATION,
            "base and stablecoin namespaces must derive to disjoint roots"
        );
        assertTrue(
            MockB20Storage.STORAGE_LOCATION != MockB20AssetStorage.STORAGE_LOCATION,
            "base and asset namespaces must derive to disjoint roots"
        );
        assertTrue(
            MockB20StablecoinStorage.STORAGE_LOCATION != MockB20AssetStorage.STORAGE_LOCATION,
            "stablecoin and asset namespaces must derive to disjoint roots"
        );
    }
}
