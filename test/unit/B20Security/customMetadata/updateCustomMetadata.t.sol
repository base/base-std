// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

contract B20SecurityUpdateCustomMetadataTest is B20SecurityTest {
    /// @notice Verifies updateCustomMetadata reverts when caller lacks METADATA_ROLE
    /// @dev Access control: gated on METADATA_ROLE (paired with the base `updateName` /
    ///      `updateSymbol` setters). Checks AccessControlUnauthorizedAccount with
    ///      METADATA_ROLE in the revert.
    function test_updateCustomMetadata_revert_unauthorized(address caller, string calldata value) public {
        _assumeValidCaller(caller);
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        security().updateCustomMetadata(METADATA_EXAMPLE_1, value);
    }

    /// @notice Verifies updateCustomMetadata reverts when key is empty
    /// @dev Per IB20Security: the entry key is always required; pass empty `value` to
    ///      remove an entry instead. Checks the InvalidMetadataKey selector.
    function test_updateCustomMetadata_revert_emptyKey(string calldata value) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        vm.expectRevert(IB20Security.InvalidMetadataKey.selector);
        security().updateCustomMetadata("", value);
    }

    /// @notice Verifies updateCustomMetadata writes the value through the getter
    /// @dev Round-trip on a fresh entry; the getter must return the written value.
    function test_updateCustomMetadata_success_writesValue(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, value);
        assertEq(security().customMetadata(METADATA_EXAMPLE_1), value, "getter must reflect the write");
    }

    /// @notice Verifies an empty value removes the entry (subsequent read returns empty string)
    /// @dev The "remove" path is explicitly part of the API: empty `value` removes the entry.
    function test_updateCustomMetadata_success_emptyValueRemoves(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, value);
        assertEq(security().customMetadata(METADATA_EXAMPLE_1), value, "test setup: entry must be set");

        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, "");
        assertEq(security().customMetadata(METADATA_EXAMPLE_1), "", "empty value must remove the entry");
    }

    /// @notice Verifies a subsequent write overwrites the previous value
    /// @dev Mutability: the latest write wins; prior value is fully discarded.
    function test_updateCustomMetadata_success_overwrites(string calldata first, string calldata second) public {
        vm.assume(bytes(first).length > 0);
        vm.assume(bytes(second).length > 0);
        vm.assume(keccak256(bytes(first)) != keccak256(bytes(second)));

        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, first);
        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, second);
        assertEq(security().customMetadata(METADATA_EXAMPLE_1), second, "overwrite must replace prior value");
    }

    /// @notice Verifies updateCustomMetadata emits CustomMetadataUpdated(key, value)
    /// @dev Event integrity for the rotation; subscribers depend on this event for off-chain
    ///      metadata-state replication.
    function test_updateCustomMetadata_success_emitsEvent(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.expectEmit(false, false, false, true, address(token));
        emit IB20Security.CustomMetadataUpdated(METADATA_EXAMPLE_1, value);
        vm.prank(admin);
        security().updateCustomMetadata(METADATA_EXAMPLE_1, value);
    }
}
