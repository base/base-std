// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Exhaustive layout spec for the `base.policy_registry` namespace.
///
/// @dev    Populates the registry with non-default values across every
///         field of `MockPolicyRegistryStorage.Layout`, then asserts
///         the raw slot value at each absolute slot matches the
///         expected encoding. This is the single comprehensive
///         storage-layout reference the Rust precompile impl must
///         reproduce byte-for-byte.
contract PolicyRegistryFullLayoutTest is PolicyRegistryTest {
    /// @notice Cross-cuts every field of MockPolicyRegistryStorage.Layout
    ///         in one populated snapshot.
    /// @dev    Field coverage in slot order:
    ///         - 0: policies (admin + exists; type recovered from the ID)
    ///         - 1: members
    ///         - 2: pendingAdmins
    ///         - 3: nextCounter
    function test_policyRegistryLayout_success_populatedSnapshotMatchesAllSlots() public {
        // ---------- Populate ----------
        // Create one of each policy type with distinct admins; bob will
        // be the staged pending admin for the allowlist policy.
        uint64 allowlistId = _createAllowlist(admin, alice);
        uint64 blocklistId = _createBlocklist(admin, attacker);

        // Add a member to each policy so the members[id][account] slots
        // are non-default.
        address[] memory allowlistMembers = new address[](1);
        allowlistMembers[0] = bob;
        vm.prank(alice);
        policyRegistry.updateAllowlist(allowlistId, true, allowlistMembers);

        address[] memory blocklistMembers = new address[](1);
        blocklistMembers[0] = alice;
        vm.prank(attacker);
        policyRegistry.updateBlocklist(blocklistId, true, blocklistMembers);

        // Stage a pending admin transfer on the allowlist policy so the
        // pendingAdmins[id] slot is non-zero.
        vm.prank(alice);
        policyRegistry.stageUpdateAdmin(allowlistId, bob);

        address registry = address(policyRegistry);

        // ---------- policies (slot 0 hashed by id) ----------
        // Allowlist policy: admin = alice; type carried by the ID's top byte.
        {
            uint256 packedA = uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(allowlistId)));
            assertEq(
                MockPolicyRegistryStorage.policyAdminFromPacked(packedA), alice, "policies[allowlistId] admin lane"
            );
            assertTrue(
                MockPolicyRegistryStorage.policyExistsFromPacked(packedA),
                "policies[allowlistId] exists bit must be set"
            );
            assertEq(
                MockPolicyRegistryStorage.policyTypeFromId(allowlistId),
                uint8(IPolicyRegistry.PolicyType.ALLOWLIST),
                "allowlistId top byte must encode ALLOWLIST"
            );
        }
        // Blocklist policy: admin = attacker; type carried by the ID's top byte.
        {
            uint256 packedB = uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(blocklistId)));
            assertEq(
                MockPolicyRegistryStorage.policyAdminFromPacked(packedB), attacker, "policies[blocklistId] admin lane"
            );
            assertTrue(
                MockPolicyRegistryStorage.policyExistsFromPacked(packedB),
                "policies[blocklistId] exists bit must be set"
            );
            assertEq(
                MockPolicyRegistryStorage.policyTypeFromId(blocklistId),
                uint8(IPolicyRegistry.PolicyType.BLOCKLIST),
                "blocklistId top byte must encode BLOCKLIST"
            );
        }

        // ---------- members (slot 1 hashed by id then account) ----------
        assertEq(
            uint256(vm.load(registry, MockPolicyRegistryStorage.policyMemberSlot(allowlistId, bob))),
            uint256(1),
            "members[allowlistId][bob] slot must be set"
        );
        assertEq(
            uint256(vm.load(registry, MockPolicyRegistryStorage.policyMemberSlot(blocklistId, alice))),
            uint256(1),
            "members[blocklistId][alice] slot must be set"
        );

        // ---------- pendingAdmins (slot 2 hashed by id) ----------
        assertEq(
            address(uint160(uint256(vm.load(registry, MockPolicyRegistryStorage.pendingAdminSlot(allowlistId))))),
            bob,
            "pendingAdmins[allowlistId] must hold bob"
        );
        // Blocklist policy has no pending admin: slot must be zero.
        assertEq(
            vm.load(registry, MockPolicyRegistryStorage.pendingAdminSlot(blocklistId)),
            bytes32(0),
            "pendingAdmins[blocklistId] must be cleared"
        );

        // ---------- nextCounter (slot 3) ----------
        // First create pays the floor (skip 0/1) → counter 2; second → 3;
        // nextCounter ends at 4 (lastCounter + 1). Compare counters
        // directly since the full IDs differ in their type byte.
        uint64 counterMask = (uint64(1) << 56) - 1;
        uint256 allowCounter = uint256(allowlistId & counterMask);
        uint256 blockCounter = uint256(blocklistId & counterMask);
        uint256 lastCounter = blockCounter > allowCounter ? blockCounter : allowCounter;
        assertEq(
            uint256(vm.load(registry, MockPolicyRegistryStorage.nextCounterSlot())),
            lastCounter + 1,
            "nextCounter slot must equal the higher counter + 1"
        );
    }
}
