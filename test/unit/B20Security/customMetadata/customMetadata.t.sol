// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecurityCustomMetadataTest is B20SecurityTest {
    /// @notice Verifies customMetadata returns the empty string for an unset entry
    /// @dev Default for any unset mapping entry is the empty string; the API contract is that
    ///      unset and explicitly-empty both read back as "". The factory does not seed any
    ///      entry at creation, so every key reads as empty on a fresh token.
    function test_customMetadata_success_emptyForUnset() public view {
        assertEq(security().customMetadata(METADATA_EXAMPLE_1), "", "unset entry must read as empty string");
        assertEq(security().customMetadata(METADATA_EXAMPLE_2), "", "unset entry must read as empty string");
        assertEq(security().customMetadata(METADATA_EXAMPLE_3), "", "unset entry must read as empty string");
    }

    /// @notice Verifies customMetadata reads back any value written via updateCustomMetadata
    /// @dev Property: setter-then-getter round-trip for arbitrary metadata values.
    function test_customMetadata_success_returnsStoredValue(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, value);
        assertEq(security().customMetadata(METADATA_EXAMPLE_1), value, "getter must return the last written value");
    }
}
