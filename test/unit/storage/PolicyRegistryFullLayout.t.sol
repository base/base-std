// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

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
        // be the staged pending admin for the allowlist policy. The first
        // `createPolicy` also lazily writes the built-in policies, populating
        // the ALWAYS_ALLOW / ALWAYS_BLOCK slots before any custom write.
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
        // Built-in slots populated by lazy init on the first create: both
        // carry a renounced (zero) admin with the exists bit set, so the
        // packed word is `1 << EXISTS_BIT`.
        {
            uint256 expectedBuiltin = MockPolicyRegistryStorage.packPolicy(address(0));
            assertEq(
                uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(0))),
                expectedBuiltin,
                "policies[ALWAYS_ALLOW_ID] must be packed(address(0)) after lazy init"
            );
            assertEq(
                uint256(
                    vm.load(
                        registry,
                        MockPolicyRegistryStorage.policySlot(
                            MockPolicyRegistryStorage.packPolicyId(uint8(IPolicyRegistry.PolicyType.ALLOWLIST), 1)
                        )
                    )
                ),
                expectedBuiltin,
                "policies[ALWAYS_BLOCK_ID] must be packed(address(0)) after lazy init"
            );
        }
        // Allowlist policy: admin = alice; type carried by the ID's top byte.
        // Layout pin on the packed word: bits 0..159 hold the admin, bits
        // 160..254 are reserved (must be zero), bit 255 is the exists flag.
        // Assertions go directly against raw bit ranges rather than through
        // codec helpers so a buggy codec can't hide a buggy layout (the
        // codec's bit math is separately verified by roundtrip tests in
        // `MockPolicyRegistrySlotHelpers.t.sol`).
        {
            uint256 packedA = uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(allowlistId)));
            assertEq(
                packedA & ((uint256(1) << 160) - 1),
                uint256(uint160(alice)),
                "policies[allowlistId] bits 0..159: admin lane"
            );
            assertEq(
                (packedA >> 160) & ((uint256(1) << 95) - 1),
                uint256(0),
                "policies[allowlistId] bits 160..254: reserved must be zero"
            );
            assertEq(packedA >> 255, uint256(1), "policies[allowlistId] bit 255: exists flag must be set");
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
                packedB & ((uint256(1) << 160) - 1),
                uint256(uint160(attacker)),
                "policies[blocklistId] bits 0..159: admin lane"
            );
            assertEq(
                (packedB >> 160) & ((uint256(1) << 95) - 1),
                uint256(0),
                "policies[blocklistId] bits 160..254: reserved must be zero"
            );
            assertEq(packedB >> 255, uint256(1), "policies[blocklistId] bit 255: exists flag must be set");
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

        // ---------- Post-renounce slot layout ----------
        // Renouncing admin must clear bits 0..159 (admin lane) AND leave
        // bit 255 (exists) set AND keep bits 160..254 (reserved) zero.
        // This is the invariant that lets `policyExists` distinguish
        // "renounced" (exists=1, admin=0) from "never created" (slot==0).
        vm.prank(attacker);
        policyRegistry.renounceAdmin(blocklistId);
        {
            uint256 packedBafter = uint256(vm.load(registry, MockPolicyRegistryStorage.policySlot(blocklistId)));
            assertEq(
                packedBafter & ((uint256(1) << 160) - 1),
                uint256(0),
                "renounced policies[blocklistId] bits 0..159: admin lane must be cleared"
            );
            assertEq(
                (packedBafter >> 160) & ((uint256(1) << 95) - 1),
                uint256(0),
                "renounced policies[blocklistId] bits 160..254: reserved must remain zero"
            );
            assertEq(
                packedBafter >> 255,
                uint256(1),
                "renounced policies[blocklistId] bit 255: exists flag must survive renunciation"
            );
        }

        // ---------- nextCounter (slot 3) ----------
        // Lazy init advances the counter from 0 to BUILTIN_POLICY_COUNT (=2)
        // on the first create; allowlistId then consumes counter 2 and
        // blocklistId consumes counter 3. nextCounter ends at lastCounter+1.
        // Compare counters directly since the full IDs differ in their type byte.
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
