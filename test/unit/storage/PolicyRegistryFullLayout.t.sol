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
    ///         in a single populated snapshot.
    /// @dev    Setup creates one ALLOWLIST and one BLOCKLIST policy
    ///         (each with admin and members), stages a pending admin
    ///         transfer on the allowlist policy, and exercises the
    ///         nextCounter slot through both creates. Then every slot
    ///         is loaded via vm.load and compared to the
    ///         independently-computed expected value.
    ///
    ///         Field coverage in slot order:
    ///         - 0: policies (packed admin+type for both ids)
    ///         - 1: members (allowlist member, blocklist member)
    ///         - 2: pendingAdmins (staged on allowlist policy)
    ///         - 3: nextCounter (advanced by 2 creates after lazy floor)
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
        // Allowlist policy: admin = alice, type = ALLOWLIST.
        {
            uint256 packedA = uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(allowlistId)));
            assertEq(
                MockPolicyRegistryStorage.policyAdminFromPacked(packedA), alice, "policies[allowlistId] admin lane"
            );
            assertEq(
                MockPolicyRegistryStorage.policyTypeFromPacked(packedA),
                uint8(IPolicyRegistry.PolicyType.ALLOWLIST),
                "policies[allowlistId] type lane"
            );
        }
        // Blocklist policy: admin = attacker, type = BLOCKLIST.
        {
            uint256 packedB = uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(blocklistId)));
            assertEq(
                MockPolicyRegistryStorage.policyAdminFromPacked(packedB), attacker, "policies[blocklistId] admin lane"
            );
            assertEq(
                MockPolicyRegistryStorage.policyTypeFromPacked(packedB),
                uint8(IPolicyRegistry.PolicyType.BLOCKLIST),
                "policies[blocklistId] type lane"
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
        // The first create pays the lazy floor (skip sentinels 0 and 1)
        // and lands counter at 3; the second create advances to 4.
        // Equivalently: nextCounter == (last id & counter mask) + 1.
        uint64 counterMask = (uint64(1) << 56) - 1;
        uint256 lastCounter =
            blocklistId > allowlistId ? uint256(blocklistId & counterMask) : uint256(allowlistId & counterMask);
        assertEq(
            uint256(vm.load(registry, MockPolicyRegistryStorage.nextCounterSlot())),
            lastCounter + 1,
            "nextCounter slot must equal the higher counter ID + 1"
        );
    }
}
