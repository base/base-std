// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `updatePolicy`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(DEFAULT_ADMIN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. UNSUPPORTED-POLICY-TYPE (`_readPolicyId(scope)` reverts on unknown scope) → `UnsupportedPolicyType`
///         3. POLICY-NOT-FOUND (`policyExists(newPolicyId) == false`) → `PolicyNotFound`
///
///         C(3, 2) = 3 pairs.
contract B20UpdatePolicyRevertOrderTest is B20Test {
    /// @dev A bytes32 value that is NOT one of the four known policy scopes (TRANSFER_SENDER,
    ///      TRANSFER_RECEIVER, TRANSFER_EXECUTOR, MINT_RECEIVER). Triggers
    ///      `UnsupportedPolicyType` when passed to `updatePolicy`.
    bytes32 internal constant UNKNOWN_POLICY_SCOPE = keccak256("unknown-scope-for-revert-order-test");

    /// @dev A uint64 that is not a registered policy ID (not ALWAYS_ALLOW, not ALWAYS_BLOCK,
    ///      and never created). Triggers `PolicyNotFound` when passed to `updatePolicy`.
    uint64 internal constant UNKNOWN_POLICY_ID = 0xdeadbeef;

    // --- Pairs where ROLE wins ---

    function test_updatePolicy_revertOrder_role_beats_unsupportedType(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        // Caller lacks DEFAULT_ADMIN_ROLE AND the scope is unknown.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updatePolicy(UNKNOWN_POLICY_SCOPE, PolicyRegistryConstants.ALWAYS_ALLOW_ID);
    }

    function test_updatePolicy_revertOrder_role_beats_policyNotFound(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        // Caller lacks role AND newPolicyId doesn't exist.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updatePolicy(B20Constants.TRANSFER_SENDER_POLICY, UNKNOWN_POLICY_ID);
    }

    // --- Pair where UNSUPPORTED-POLICY-TYPE wins ---

    function test_updatePolicy_revertOrder_unsupportedType_beats_policyNotFound() public {
        // Both: scope is unknown AND newPolicyId doesn't exist. The scope read (`_readPolicyId`)
        // runs before the policy-existence check.

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.UnsupportedPolicyType.selector, UNKNOWN_POLICY_SCOPE));
        token.updatePolicy(UNKNOWN_POLICY_SCOPE, UNKNOWN_POLICY_ID);
    }
}
