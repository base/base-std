// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

/// @title Sequential revert-order test for `updateExtraMetadata`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(METADATA_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. INVALID-METADATA-KEY (`bytes(key).length == 0`) → `InvalidMetadataKey`
///
///         Walks from all conditions broken to success, fixing one per step.
contract B20AssetUpdateExtraMetadataRevertOrderTest is B20AssetTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_updateExtraMetadata_revertOrder(address caller, string calldata value) public {
        // Exclude precompiles (which can distort msg.sender) and admin (needed
        // internally by _grantRole to approve the role grant).
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        // 1. ROLE fires: caller lacks METADATA_ROLE AND key is empty.
        //    The role modifier runs before the body's empty-key check.
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        asset().updateExtraMetadata("", value);

        // Fix: grant METADATA_ROLE to caller.
        _grantRole(B20Constants.METADATA_ROLE, caller);

        // 2. INVALID-METADATA-KEY fires: caller now holds the role, but key is still empty.
        vm.prank(caller);
        vm.expectRevert(IB20Asset.InvalidMetadataKey.selector);
        asset().updateExtraMetadata("", value);

        // Fix: pass a non-empty key.

        // Success: all conditions resolved.
        vm.prank(caller);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
    }
}
