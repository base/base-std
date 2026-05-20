// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20UpdatePolicyTest is B20Test {
    /// @notice Verifies updatePolicy reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only the admin may reassign policy slots; checks AccessControlUnauthorizedAccount.
    ///      Auth fires before policy-type / registry checks, so any bytes32 fuzz is fine here.
    function test_updatePolicy_revert_unauthorized(address caller, bytes32 policyType, uint64 newPolicyId) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updatePolicy(policyType, newPolicyId);
    }

    /// @notice Verifies updatePolicy reverts when the target policy id does not exist in the registry
    /// @dev Cross-precompile guard; checks PolicyNotFound() error. Fuzzes well-formed but
    ///      uncreated registry IDs so the registry-side malformed check passes and the
    ///      not-found path fires from MockB20.
    function test_updatePolicy_revert_policyNotFound(uint8 typeIdx, uint64 seed) public {
        bytes32 policyType = _knownPolicyType(typeIdx);
        uint64 newPolicyId = _wellFormedUncreatedPolicyId(seed);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyNotFound.selector, newPolicyId));
        token.updatePolicy(policyType, newPolicyId);
    }

    /// @notice Verifies updatePolicy reverts when the policyType is not one of the base-token's
    ///         four supported types and is not added by a variant.
    /// @dev Strictness on writes: there is no fallback mapping, so unsupported policyTypes are
    ///      rejected explicitly. Uses a built-in policy id so the registry check passes; the
    ///      revert must come from `_writePolicyId`'s UnsupportedPolicyType branch.
    function test_updatePolicy_revert_unsupportedPolicyType(bytes32 policyType, uint64 newPolicyIdSeed) public {
        vm.assume(!_isKnownPolicyType(policyType));
        uint64 newPolicyId = newPolicyIdSeed % 2 == 0
            ? PolicyRegistryConstants.ALWAYS_ALLOW_ID
            : PolicyRegistryConstants.ALWAYS_BLOCK_ID;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.UnsupportedPolicyType.selector, policyType));
        token.updatePolicy(policyType, newPolicyId);
    }

    /// @notice Verifies updatePolicy succeeds for built-in id 0 (always-allow)
    /// @dev Built-ins are always valid targets across all supported policy types
    function test_updatePolicy_success_builtinAllow(uint8 typeIdx) public {
        bytes32 policyType = _knownPolicyType(typeIdx);
        _setPolicy(policyType, PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        assertEq(token.policyId(policyType), PolicyRegistryConstants.ALWAYS_ALLOW_ID, "slot must be ALWAYS_ALLOW_ID");
    }

    /// @notice Verifies updatePolicy succeeds for built-in id 1 (always-reject)
    /// @dev Built-ins are always valid targets across all supported policy types
    function test_updatePolicy_success_builtinReject(uint8 typeIdx) public {
        bytes32 policyType = _knownPolicyType(typeIdx);
        _setPolicy(policyType, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(token.policyId(policyType), PolicyRegistryConstants.ALWAYS_BLOCK_ID, "slot must be ALWAYS_BLOCK_ID");
    }

    /// @notice Verifies updatePolicy writes the new id to the slot
    /// @dev Read-after-write: policyId(policyType) returns newPolicyId
    function test_updatePolicy_success_writesSlot(uint8 typeIdx, uint64 newPolicyId) public {
        bytes32 policyType = _knownPolicyType(typeIdx);
        // Bound to a registry-supported id.
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;
        _setPolicy(policyType, newPolicyId);
        assertEq(token.policyId(policyType), newPolicyId, "slot must equal newPolicyId after write");
    }

    /// @notice Verifies updatePolicy on one lane leaves other lanes unchanged
    /// @dev Policy slots are packed into shared storage slots (one for transfer-side,
    ///      one for mint-side). A buggy write mask that doesn't isolate the target lane
    ///      would silently zero adjacent lanes. We set every supported policy slot to
    ///      ALWAYS_BLOCK first, then update TRANSFER_SENDER to ALWAYS_ALLOW, and verify
    ///      the other three slots are still ALWAYS_BLOCK.
    function test_updatePolicy_success_writeIsolatedToTargetLane() public {
        _setPolicy(B20Constants.TRANSFER_SENDER, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_RECEIVER, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.MINT_RECEIVER, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        _setPolicy(B20Constants.TRANSFER_SENDER, PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        assertEq(token.policyId(B20Constants.TRANSFER_SENDER), PolicyRegistryConstants.ALWAYS_ALLOW_ID, "SENDER updated");
        assertEq(token.policyId(B20Constants.TRANSFER_RECEIVER), PolicyRegistryConstants.ALWAYS_BLOCK_ID, "RECEIVER must be untouched");
        assertEq(token.policyId(B20Constants.TRANSFER_EXECUTOR), PolicyRegistryConstants.ALWAYS_BLOCK_ID, "EXECUTOR must be untouched");
        assertEq(token.policyId(B20Constants.MINT_RECEIVER), PolicyRegistryConstants.ALWAYS_BLOCK_ID, "MINT_RECEIVER must be untouched");
    }

    /// @notice Verifies updatePolicy emits PolicyUpdated(policyType, oldId, newId)
    /// @dev Event integrity; canonical PolicyUpdated emission test.
    ///      Fresh slot has oldId == ALWAYS_ALLOW_ID (0); the first write transitions from there.
    function test_updatePolicy_success_emitsPolicyUpdated(uint8 typeIdx, uint64 newPolicyId) public {
        bytes32 policyType = _knownPolicyType(typeIdx);
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.PolicyUpdated(policyType, PolicyRegistryConstants.ALWAYS_ALLOW_ID, newPolicyId);
        _setPolicy(policyType, newPolicyId);
    }
}
