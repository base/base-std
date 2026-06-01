// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @title Differential check-order tests for `updateBlocklist`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. POLICY-NOT-FOUND (`_requireCustom`: packed == 0) → `PolicyNotFound`
///         2. INCOMPATIBLE-TYPE (`_typeOf(policyId) != BLOCKLIST`) → `IncompatiblePolicyType`
///         3. UNAUTHORIZED (`_decodeAdmin(packed) != msg.sender`) → `Unauthorized`
///         4. BATCH-SIZE (inside `_batchSetMembers`) → `BatchSizeTooLarge`
///
///         C(4, 2) = 6 pairs. Mirror of `updateAllowlist_revertOrder.t.sol` with
///         ALLOWLIST and BLOCKLIST roles swapped.
contract PolicyRegistryUpdateBlocklistRevertOrderTest is PolicyRegistryTest {
    // ---------------------------------------------------------------
    // Pairs where POLICY-NOT-FOUND wins
    // ---------------------------------------------------------------

    /// @notice POLICY-NOT-FOUND beats INCOMPATIBLE-TYPE.
    /// @dev policyId encodes as ALLOWLIST (top byte 1, incompatible for updateBlocklist)
    ///      AND the policy has never been created (packed == 0).
    ///      PolicyNotFound fires before the type discriminator is examined.
    function test_updateBlocklist_revertOrder_policyNotFound_beats_incompatiblePolicyType(uint56 counter) public {
        counter = uint56(bound(uint256(counter), 2, type(uint56).max));
        // top byte 1 = ALLOWLIST; would trigger IncompatiblePolicyType if the policy existed.
        uint64 policyId = (uint64(1) << 56) | uint64(counter);
        address[] memory empty = new address[](0);

        // Both conditions apply independently:
        // - PolicyNotFound: policyId has never been created.
        // - IncompatiblePolicyType: policyId encodes as ALLOWLIST, not BLOCKLIST.
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateBlocklist(policyId, true, empty);
    }

    /// @notice POLICY-NOT-FOUND beats UNAUTHORIZED.
    /// @dev policyId encodes as BLOCKLIST (so IncompatiblePolicyType does not apply)
    ///      AND has never been created (PolicyNotFound fires), AND caller is non-zero
    ///      (Unauthorized would fire if policyId existed as BLOCKLIST).
    function test_updateBlocklist_revertOrder_policyNotFound_beats_unauthorized(address caller, uint56 counter) public {
        _assumeValidCaller(caller);
        counter = uint56(bound(uint256(counter), 2, type(uint56).max));
        // top byte 0 = BLOCKLIST; IncompatiblePolicyType would not apply if the policy existed.
        uint64 policyId = uint64(counter);
        address[] memory empty = new address[](0);

        // Both conditions apply independently:
        // - PolicyNotFound: policyId has never been created (packed == 0).
        // - Unauthorized: _decodeAdmin(0) == address(0) != caller.
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateBlocklist(policyId, true, empty);
    }

    /// @notice POLICY-NOT-FOUND beats BATCH-SIZE.
    /// @dev policyId has never been created (PolicyNotFound fires) AND accounts.length
    ///      exceeds MAX_BATCH_SIZE (BatchSizeTooLarge would fire inside _batchSetMembers
    ///      if the policy existed and all earlier checks passed).
    function test_updateBlocklist_revertOrder_policyNotFound_beats_batchSizeTooLarge(uint56 counter, uint8 overflow)
        public
    {
        counter = uint56(bound(uint256(counter), 2, type(uint56).max));
        uint64 policyId = uint64(counter); // BLOCKLIST type, not created
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);

        // Both conditions apply independently:
        // - PolicyNotFound: policyId has never been created.
        // - BatchSizeTooLarge: accounts.length > MAX_BATCH_SIZE.
        vm.expectRevert(IPolicyRegistry.PolicyNotFound.selector);
        policyRegistry.updateBlocklist(policyId, true, accounts);
    }

    // ---------------------------------------------------------------
    // Pairs where INCOMPATIBLE-TYPE wins
    // ---------------------------------------------------------------

    /// @notice INCOMPATIBLE-TYPE beats UNAUTHORIZED.
    /// @dev Policy exists as ALLOWLIST (incompatible for updateBlocklist) AND caller
    ///      is not the policy admin (Unauthorized would fire if the type check were absent).
    function test_updateBlocklist_revertOrder_incompatiblePolicyType_beats_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        // Create an ALLOWLIST policy with `alice` as admin.
        uint64 policyId = _createAllowlist(admin, alice);
        vm.assume(caller != alice);
        address[] memory empty = new address[](0);

        // Both conditions apply independently:
        // - IncompatiblePolicyType: policy is ALLOWLIST, updateBlocklist requires BLOCKLIST.
        // - Unauthorized: caller is not alice (the policy admin).
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.updateBlocklist(policyId, true, empty);
    }

    /// @notice INCOMPATIBLE-TYPE beats BATCH-SIZE.
    /// @dev Policy exists as ALLOWLIST AND accounts.length exceeds MAX_BATCH_SIZE.
    ///      Caller is the policy admin so Unauthorized does not apply; only type and
    ///      batch-size conditions compete.
    function test_updateBlocklist_revertOrder_incompatiblePolicyType_beats_batchSizeTooLarge(uint8 overflow) public {
        // Create an ALLOWLIST policy with alice as admin; call as alice (no Unauthorized).
        uint64 policyId = _createAllowlist(admin, alice);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);

        // Both conditions apply independently:
        // - IncompatiblePolicyType: policy is ALLOWLIST, updateBlocklist requires BLOCKLIST.
        // - BatchSizeTooLarge: accounts.length > MAX_BATCH_SIZE.
        vm.prank(alice);
        vm.expectRevert(IPolicyRegistry.IncompatiblePolicyType.selector);
        policyRegistry.updateBlocklist(policyId, true, accounts);
    }

    // ---------------------------------------------------------------
    // Pairs where UNAUTHORIZED wins
    // ---------------------------------------------------------------

    /// @notice UNAUTHORIZED beats BATCH-SIZE.
    /// @dev Policy exists as BLOCKLIST (IncompatiblePolicyType does not apply) AND
    ///      caller is not the policy admin AND accounts.length exceeds MAX_BATCH_SIZE.
    ///      Unauthorized fires before _batchSetMembers runs its batch-size guard.
    function test_updateBlocklist_revertOrder_unauthorized_beats_batchSizeTooLarge(address caller, uint8 overflow)
        public
    {
        _assumeValidCaller(caller);
        // Create a BLOCKLIST policy with alice as admin; caller is not alice.
        uint64 policyId = _createBlocklist(admin, alice);
        vm.assume(caller != alice);
        uint256 n = MAX_BATCH_SIZE + 1 + (uint256(overflow) % 16);
        address[] memory accounts = _makeAccounts(n);

        // Both conditions apply independently:
        // - Unauthorized: caller is not alice (the policy admin).
        // - BatchSizeTooLarge: accounts.length > MAX_BATCH_SIZE.
        vm.prank(caller);
        vm.expectRevert(IPolicyRegistry.Unauthorized.selector);
        policyRegistry.updateBlocklist(policyId, true, accounts);
    }
}
