// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "test/lib/B20AssetTest.sol";

import {IB20} from "src/interfaces/IB20.sol";

import {B20Constants} from "src/lib/B20Constants.sol";
import {MockB20Storage, MockB20RedeemStorage} from "test/lib/mocks/MockB20Storage.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20AssetUpdatePolicyTest is B20AssetTest {
    /// @notice Verifies updatePolicy(REDEEM_SENDER_POLICY, ...) reverts when caller lacks admin
    /// @dev Access control inherited from base: updatePolicy is `onlyRole(DEFAULT_ADMIN_ROLE)`
    ///      regardless of which policyScope is being written.
    function test_updatePolicy_revert_unauthorized_redeemSender(address caller, bool useBlock) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        // Use a sentinel id (ALWAYS_ALLOW or ALWAYS_BLOCK) so no registry setup is needed.
        uint64 newPolicyId =
            useBlock ? PolicyRegistryConstants.ALWAYS_BLOCK_ID : PolicyRegistryConstants.ALWAYS_ALLOW_ID;

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updatePolicy(REDEEM_SENDER_POLICY, newPolicyId);
    }

    /// @notice Verifies the REDEEM_SENDER_POLICY write only touches the redeem-side packed slot
    /// @dev Storage isolation: the variant override writes to `MockB20RedeemStorage.redeemPolicyIds`,
    ///      and must not touch the base `transferPolicyIds` / `mintPolicyIds` slots. Paired slot
    ///      assertions confirm both invariants — the new lane gets the value, and the base lanes
    ///      keep their pre-write contents.
    function test_updatePolicy_success_redeemSenderIsolatedToVariantSlot() public {
        // Snapshot the base slots before the write so we can assert they don't change.
        bytes32 transferBefore = vm.load(address(token), MockB20Storage.transferPolicyIdsSlot());
        bytes32 mintBefore = vm.load(address(token), MockB20Storage.mintPolicyIdsSlot());

        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // Variant lane got the write (low 64 bits of redeemPolicyIds).
        uint256 redeemPacked = uint256(vm.load(address(token), MockB20RedeemStorage.redeemPolicyIdsSlot()));
        assertEq(
            uint64(redeemPacked),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "redeemPolicyIds lane 0 must hold the written value"
        );

        // Base slots are unchanged.
        assertEq(
            vm.load(address(token), MockB20Storage.transferPolicyIdsSlot()),
            transferBefore,
            "transferPolicyIds slot must NOT change on a REDEEM_SENDER_POLICY write"
        );
        assertEq(
            vm.load(address(token), MockB20Storage.mintPolicyIdsSlot()),
            mintBefore,
            "mintPolicyIds slot must NOT change on a REDEEM_SENDER_POLICY write"
        );
    }

    /// @notice Verifies the REDEEM_SENDER_POLICY write reads back via policyId
    /// @dev End-to-end round-trip across the variant override's `_writePolicyId` and
    ///      `_readPolicyId` arms.
    function test_updatePolicy_success_redeemSenderReadback() public {
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(
            token.policyId(REDEEM_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "policyId must reflect the write"
        );
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_ALLOW_ID);
        assertEq(
            token.policyId(REDEEM_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "policyId must reflect the second write"
        );
    }

    /// @notice Verifies the variant override's `_writePolicyId` preserves the redeem slot's high lanes
    /// @dev `redeemPolicyIds` reserves three high lanes for future redeem-side policy types. The
    ///      variant override must mask only lane 0 when writing REDEEM_SENDER_POLICY — a buggy
    ///      mask-all-then-OR would clobber the reserved lanes. Pre-poke the reserved bits via
    ///      vm.store then write and assert preservation.
    function test_updatePolicy_success_redeemSenderPreservesReservedLanes() public {
        // Pre-poke a non-zero pattern into the upper lanes of the redeem packed slot.
        uint256 reservedPattern = (uint256(0xDEADBEEFCAFEBABE) << 64) | (uint256(0x1234567890ABCDEF) << 128)
            | (uint256(0xFEDCBA0987654321) << 192);
        vm.store(address(token), MockB20RedeemStorage.redeemPolicyIdsSlot(), bytes32(reservedPattern));

        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        uint256 after_ = uint256(vm.load(address(token), MockB20RedeemStorage.redeemPolicyIdsSlot()));
        assertEq(
            uint64(after_),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "lane 0 must hold the written REDEEM_SENDER_POLICY id"
        );
        assertEq(
            after_ & ~uint256(type(uint64).max), reservedPattern, "upper three lanes must be preserved bit-for-bit"
        );
    }

    /// @notice Verifies updatePolicy still falls through to base types via super
    /// @dev The override checks REDEEM_SENDER_POLICY then `super`s; base types still work
    ///      end-to-end (write touches base packed slot, readback returns the written value).
    ///      The ALWAYS_BLOCK sentinel is used to avoid having to register a custom policy.
    function test_updatePolicy_success_baseTypesStillRouteThroughSuper() public {
        vm.prank(admin);
        token.updatePolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(
            token.policyId(B20Constants.TRANSFER_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "TRANSFER_SENDER write must persist"
        );

        // And the redeem slot is untouched by a base-side write (still ALWAYS_BLOCK_ID from creation).
        assertEq(
            token.policyId(REDEEM_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "REDEEM_SENDER must not be affected by base writes"
        );
    }
}
