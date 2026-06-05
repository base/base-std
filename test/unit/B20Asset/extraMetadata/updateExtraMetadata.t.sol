// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

contract B20AssetUpdateExtraMetadataTest is B20AssetTest {
    /// @notice Verifies updateExtraMetadata reverts when caller lacks METADATA_ROLE
    /// @dev Access control: gated on METADATA_ROLE (paired with the base `updateName` /
    ///      `updateSymbol` setters). Checks AccessControlUnauthorizedAccount with
    ///      METADATA_ROLE in the revert.
    function test_updateExtraMetadata_revert_unauthorized(address caller, string calldata value) public {
        _assumeValidCaller(caller);
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
    }

    /// @notice Verifies updateExtraMetadata reverts when key is empty
    /// @dev Per IB20Asset: the entry key is always required; pass empty `value` to
    ///      remove an entry instead. Checks the InvalidMetadataKey selector.
    function test_updateExtraMetadata_revert_emptyKey(string calldata value) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        vm.expectRevert(IB20Asset.InvalidMetadataKey.selector);
        asset().updateExtraMetadata("", value);
    }

    /// @notice Verifies updateExtraMetadata writes the value through the getter
    /// @dev Round-trip on a fresh entry; the getter must return the written value.
    function test_updateExtraMetadata_success_writesValue(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), value, "getter must reflect the write");
    }

    /// @notice Verifies an empty value removes the entry (subsequent read returns empty string)
    /// @dev The "remove" path is explicitly part of the API: empty `value` removes the entry.
    function test_updateExtraMetadata_success_emptyValueRemoves(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), value, "test setup: entry must be set");

        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, "");
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), "", "empty value must remove the entry");
    }

    /// @notice Verifies a subsequent write overwrites the previous value
    /// @dev Mutability: the latest write wins; prior value is fully discarded.
    function test_updateExtraMetadata_success_overwrites(string calldata first, string calldata second) public {
        vm.assume(bytes(first).length > 0);
        vm.assume(bytes(second).length > 0);
        vm.assume(keccak256(bytes(first)) != keccak256(bytes(second)));

        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, first);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, second);
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), second, "overwrite must replace prior value");
    }

    /// @notice Verifies updateExtraMetadata emits ExtraMetadataUpdated(key, value)
    /// @dev Event integrity for the rotation; subscribers depend on this event for off-chain
    ///      metadata-state replication.
    function test_updateExtraMetadata_success_emitsEvent(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Asset.ExtraMetadataUpdated(METADATA_EXAMPLE_1, value);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
    }
}
