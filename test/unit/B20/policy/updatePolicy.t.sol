// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20UpdatePolicyTest is B20Test {
    /// @notice Reads the policy id stored in the slot lane that
    ///         corresponds to `policyScope`, via raw `vm.load` and the
    ///         per-lane decoder helpers on `MockB20Storage`.
    /// @dev    The four base-token policy types are packed across two
    ///         slots:
    ///         - `transferPolicyIds` (lane 0: SENDER, 1: RECEIVER, 2: EXECUTOR)
    ///         - `mintPolicyIds` (lane 0: RECEIVER)
    ///         This helper routes to the right slot + lane decoder so
    ///         tests can assert the slot reflects the surface
    ///         `policyId(policyScope)` return.
    function _readPolicyLane(bytes32 policyScope) internal view returns (uint64) {
        if (policyScope == B20Constants.MINT_RECEIVER_POLICY) {
            return
                MockB20Storage.mintReceiverPolicyId(
                    uint256(vm.load(address(token), MockB20Storage.mintPolicyIdsSlot()))
                );
        }
        uint256 transferPacked = uint256(vm.load(address(token), MockB20Storage.transferPolicyIdsSlot()));
        if (policyScope == B20Constants.TRANSFER_SENDER_POLICY) {
            return MockB20Storage.transferSenderPolicyId(transferPacked);
        }
        if (policyScope == B20Constants.TRANSFER_RECEIVER_POLICY) {
            return MockB20Storage.transferReceiverPolicyId(transferPacked);
        }
        // TRANSFER_EXECUTOR — the four supported types are exhaustive
        // for this helper; callers always pass a known policy type via
        // `_knownPolicyType` or the named constants.
        return MockB20Storage.transferExecutorPolicyId(transferPacked);
    }

    /// @notice Verifies updatePolicy reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only the admin may reassign policy slots; checks AccessControlUnauthorizedAccount.
    ///      Auth fires before policy-type / registry checks, so any bytes32 fuzz is fine here.
    function test_updatePolicy_revert_unauthorized(address caller, bytes32 policyScope, uint64 newPolicyId) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updatePolicy(policyScope, newPolicyId);
    }

    /// @notice Verifies updatePolicy reverts when the target policy id does not exist in the registry
    /// @dev Cross-precompile guard; checks PolicyNotFound() error. Fuzzes well-formed but
    ///      uncreated registry IDs so the registry-side malformed check passes and the
    ///      not-found path fires from MockB20.
    function test_updatePolicy_revert_policyNotFound(uint8 typeIdx, uint64 seed) public {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        uint64 newPolicyId = _wellFormedUncreatedPolicyId(seed);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyNotFound.selector, newPolicyId));
        token.updatePolicy(policyScope, newPolicyId);
    }

    /// @notice Verifies updatePolicy reverts when the policyScope is not one of the base-token's
    ///         four supported types and is not added by a variant.
    /// @dev Strictness on writes: there is no fallback mapping, so unsupported policyTypes are
    ///      rejected explicitly. Uses a built-in policy id so the registry check passes; the
    ///      revert must come from `_writePolicyId`'s UnsupportedPolicyType branch.
    function test_updatePolicy_revert_unsupportedPolicyType(bytes32 policyScope, uint64 newPolicyIdSeed) public {
        vm.assume(!_isKnownPolicyType(policyScope));
        uint64 newPolicyId = newPolicyIdSeed % 2 == 0
            ? PolicyRegistryConstants.ALWAYS_ALLOW_ID
            : PolicyRegistryConstants.ALWAYS_BLOCK_ID;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.UnsupportedPolicyType.selector, policyScope));
        token.updatePolicy(policyScope, newPolicyId);
    }

    /// @notice Verifies updatePolicy succeeds for built-in id 0 (always-allow)
    /// @dev Built-ins are always valid targets across all supported policy types.
    ///      Paired slot assertion: the packed slot lane corresponding
    ///      to `policyScope` reads back as ALWAYS_ALLOW_ID.
    function test_updatePolicy_success_builtinAllow(uint8 typeIdx) public {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        _setPolicy(policyScope, PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        assertEq(token.policyId(policyScope), PolicyRegistryConstants.ALWAYS_ALLOW_ID, "slot must be ALWAYS_ALLOW_ID");
        assertEq(
            _readPolicyLane(policyScope),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "packed-slot lane must hold ALWAYS_ALLOW_ID"
        );
    }

    /// @notice Verifies updatePolicy succeeds for built-in id 1 (always-reject)
    /// @dev Built-ins are always valid targets across all supported policy types.
    ///      Paired slot assertion confirms the packed-slot lane reflects the write.
    function test_updatePolicy_success_builtinReject(uint8 typeIdx) public {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        _setPolicy(policyScope, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(token.policyId(policyScope), PolicyRegistryConstants.ALWAYS_BLOCK_ID, "slot must be ALWAYS_BLOCK_ID");
        assertEq(
            _readPolicyLane(policyScope),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "packed-slot lane must hold ALWAYS_BLOCK_ID"
        );
    }

    /// @notice Verifies updatePolicy writes the new id to the slot
    /// @dev Read-after-write: policyId(policyScope) returns newPolicyId.
    ///      Paired slot assertion confirms the packed-slot lane reflects newPolicyId.
    function test_updatePolicy_success_writesSlot(uint8 typeIdx, uint64 newPolicyId) public {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        // Bound to a registry-supported id.
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;
        _setPolicy(policyScope, newPolicyId);
        assertEq(token.policyId(policyScope), newPolicyId, "slot must equal newPolicyId after write");
        assertEq(_readPolicyLane(policyScope), newPolicyId, "packed-slot lane must equal newPolicyId");
    }

    /// @notice Verifies updatePolicy on one lane leaves other lanes unchanged
    /// @dev Policy slots are packed into shared storage slots (one for transfer-side,
    ///      one for mint-side). A buggy write mask that doesn't isolate the target lane
    ///      would silently zero adjacent lanes. We set every supported policy slot to
    ///      ALWAYS_BLOCK first, then update TRANSFER_SENDER_POLICY to ALWAYS_ALLOW, and verify
    ///      the other three slots are still ALWAYS_BLOCK.
    ///      Paired slot assertions confirm each lane independently via
    ///      the per-lane decoders on `MockB20Storage`.
    function test_updatePolicy_success_writeIsolatedToTargetLane() public {
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        assertEq(
            token.policyId(B20Constants.TRANSFER_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "SENDER updated"
        );
        assertEq(
            token.policyId(B20Constants.TRANSFER_RECEIVER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "RECEIVER must be untouched"
        );
        assertEq(
            token.policyId(B20Constants.TRANSFER_EXECUTOR_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "EXECUTOR must be untouched"
        );
        assertEq(
            token.policyId(B20Constants.MINT_RECEIVER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "MINT_RECEIVER_POLICY must be untouched"
        );

        // Paired packed-slot assertions: explicitly read the packed
        // slot and decode every lane to confirm the write mask only
        // touched lane 0 of transferPolicyIds.
        uint256 transferPacked = uint256(vm.load(address(token), MockB20Storage.transferPolicyIdsSlot()));
        uint256 mintPacked = uint256(vm.load(address(token), MockB20Storage.mintPolicyIdsSlot()));
        assertEq(
            MockB20Storage.transferSenderPolicyId(transferPacked),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "transfer SENDER lane updated"
        );
        assertEq(
            MockB20Storage.transferReceiverPolicyId(transferPacked),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "transfer RECEIVER lane untouched"
        );
        assertEq(
            MockB20Storage.transferExecutorPolicyId(transferPacked),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "transfer EXECUTOR lane untouched"
        );
        assertEq(
            MockB20Storage.mintReceiverPolicyId(mintPacked),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "mint RECEIVER lane untouched"
        );
    }

    /// @notice Verifies updatePolicy emits PolicyUpdated(policyScope, oldId, newId)
    /// @dev Event integrity; canonical PolicyUpdated emission test.
    ///      Fresh slot has oldId == ALWAYS_ALLOW_ID (0); the first write transitions from there.
    function test_updatePolicy_success_emitsPolicyUpdated(uint8 typeIdx, uint64 newPolicyId) public {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.PolicyUpdated(policyScope, PolicyRegistryConstants.ALWAYS_ALLOW_ID, newPolicyId);
        _setPolicy(policyScope, newPolicyId);
    }
}
