// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetExtraMetadataTest is B20AssetTest {
    /// @notice Verifies extraMetadata returns the empty string for an unset entry
    /// @dev Default for any unset mapping entry is the empty string; the API contract is that
    ///      unset and explicitly-empty both read back as "". The factory does not seed any
    ///      entry at creation, so every key reads as empty on a fresh token.
    function test_extraMetadata_success_emptyForUnset() public view {
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), "", "unset entry must read as empty string");
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_2), "", "unset entry must read as empty string");
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_3), "", "unset entry must read as empty string");
    }

    /// @notice Verifies extraMetadata reads back any value written via updateExtraMetadata
    /// @dev Property: setter-then-getter round-trip for arbitrary metadata values.
    function test_extraMetadata_success_returnsStoredValue(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), value, "getter must return the last written value");
    }
}
