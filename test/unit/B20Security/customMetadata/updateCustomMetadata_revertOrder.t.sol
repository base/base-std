// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

/// @title Sequential revert-order test for `updateCustomMetadata`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(METADATA_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. INVALID-IDENTIFIER-TYPE (`bytes(identifierType).length == 0`) → `InvalidIdentifierType`
///
///         Walks from all conditions broken to success, fixing one per step.
contract B20SecurityUpdateCustomMetadataRevertOrderTest is B20SecurityTest {
    /// @notice Walks through every revert in canonical order, fixing one per step, ending at success.
    function test_updateCustomMetadata_revertOrder(address caller, string calldata value) public {
        // Exclude precompiles (which can distort msg.sender) and admin (needed
        // internally by _grantRole to approve the role grant).
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        // 1. ROLE fires: caller lacks METADATA_ROLE AND identifierType is empty.
        //    The role modifier runs before the body's empty-type check.
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        security().updateCustomMetadata("", value);

        // Fix: grant METADATA_ROLE to caller.
        _grantRole(B20Constants.METADATA_ROLE, caller);

        // 2. INVALID-IDENTIFIER-TYPE fires: caller now holds the role, but
        //    identifierType is still empty.
        vm.prank(caller);
        vm.expectRevert(IB20Security.InvalidIdentifierType.selector);
        security().updateCustomMetadata("", value);

        // Fix: pass a non-empty identifierType.

        // Success: all conditions resolved.
        vm.prank(caller);
        security().updateCustomMetadata(METADATA_CATEGORY, value);
    }
}
