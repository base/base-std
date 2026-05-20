// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20UpdatePolicyTest is B20Test {
    /// @notice Verifies updatePolicy reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only the admin may reassign policy slots; checks AccessControlUnauthorizedAccount
    function test_updatePolicy_revert_unauthorized(address caller, bytes32 policyType, uint64 newPolicyId) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN_ROLE)
        );
        token.updatePolicy(policyType, newPolicyId);
    }

    /// @notice Verifies updatePolicy reverts when the target policy id does not exist in the registry
    /// @dev Cross-precompile guard; checks PolicyNotFound() error.
    ///      MockPolicyRegistry only knows ids 0 and type(uint64).max; everything else is unknown.
    function test_updatePolicy_revert_policyNotFound(bytes32 policyType, uint64 newPolicyId) public {
        vm.assume(newPolicyId != ALWAYS_ALLOW && newPolicyId != ALWAYS_REJECT);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyNotFound.selector, newPolicyId));
        token.updatePolicy(policyType, newPolicyId);
    }

    /// @notice Verifies updatePolicy succeeds for built-in id 0 (always-allow)
    /// @dev Built-ins are always valid targets
    function test_updatePolicy_success_builtinAllow(bytes32 policyType) public {
        _setPolicy(policyType, ALWAYS_ALLOW);
        assertEq(token.policyId(policyType), ALWAYS_ALLOW, "slot must be ALWAYS_ALLOW");
    }

    /// @notice Verifies updatePolicy succeeds for built-in id type(uint64).max (always-reject)
    /// @dev Built-ins are always valid targets
    function test_updatePolicy_success_builtinReject(bytes32 policyType) public {
        _setPolicy(policyType, ALWAYS_REJECT);
        assertEq(token.policyId(policyType), ALWAYS_REJECT, "slot must be ALWAYS_REJECT");
    }

    /// @notice Verifies updatePolicy writes the new id to the slot
    /// @dev Read-after-write: policyId(policyType) returns newPolicyId
    function test_updatePolicy_success_writesSlot(bytes32 policyType, uint64 newPolicyId) public {
        // Bound to a registry-supported id.
        newPolicyId = newPolicyId % 2 == 0 ? ALWAYS_ALLOW : ALWAYS_REJECT;
        _setPolicy(policyType, newPolicyId);
        assertEq(token.policyId(policyType), newPolicyId, "slot must equal newPolicyId after write");
    }

    /// @notice Verifies updatePolicy emits PolicyUpdated(policyType, oldId, newId)
    /// @dev Event integrity; canonical PolicyUpdated emission test.
    ///      Fresh slot has oldId == ALWAYS_ALLOW (0); the first write transitions from there.
    function test_updatePolicy_success_emitsPolicyUpdated(bytes32 policyType, uint64 newPolicyId) public {
        newPolicyId = newPolicyId % 2 == 0 ? ALWAYS_ALLOW : ALWAYS_REJECT;

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.PolicyUpdated(policyType, ALWAYS_ALLOW, newPolicyId);
        _setPolicy(policyType, newPolicyId);
    }
}
