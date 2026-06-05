// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Self-tests for `MockPolicyRegistryStorage`'s slot-derivation
///         and packed-slot codec helpers.
///
/// @dev    Each test creates / mutates registry state via the
///         IPolicyRegistry surface, reads the helper-computed slot via
///         `vm.load`, and asserts the slot encodes the same value the
///         surface returns.
contract MockPolicyRegistrySlotHelpersTest is PolicyRegistryTest {
    /// @notice Verifies `policySlot(id)` locates the packed (admin, exists)
    ///         word `createPolicy` writes. PolicyType is recovered from the
    ///         policy ID, not from storage.
    function test_policySlot_success_locatesPackedPolicy(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        uint64 policyId = _createAllowlist(admin, policyAdmin);

        uint256 packed = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)));

        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(packed),
            policyAdmin,
            "policyAdminFromPacked must extract the admin written by createPolicy"
        );
        assertTrue(
            MockPolicyRegistryStorage.policyExistsFromPacked(packed),
            "policyExistsFromPacked must report true after createPolicy"
        );
    }

    /// @notice Verifies `policySlot(id)` is zero for a never-created id.
    /// @dev    `policies[id] == 0` is the "never created" sentinel; created
    ///         policies keep the exists bit set even after `renounceAdmin`.
    function test_policySlot_success_zeroForUncreatedId(uint64 seed) public view {
        uint64 uncreated = _wellFormedUncreatedPolicyId(seed);
        assertEq(
            vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(uncreated)),
            bytes32(0),
            "policySlot must be zero for an uncreated id"
        );
    }

    /// @notice Verifies `policyMemberSlot(id, account)` locates the bool
    ///         membership flag for an allowlist add.
    /// @dev    Set membership via `updateAllowlist`, then read the
    ///         derived slot — must equal bytes32(uint256(1)).
    function test_policyMemberSlot_success_locatesMembershipBit(address policyAdmin, address account) public {
        vm.assume(policyAdmin != address(0));
        _assumeValidCaller(account);

        uint64 policyId = _createAllowlist(admin, policyAdmin);

        address[] memory accounts = new address[](1);
        accounts[0] = account;

        vm.prank(policyAdmin);
        policyRegistry.updateAllowlist(policyId, true, accounts);

        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policyMemberSlot(policyId, account))),
            uint256(1),
            "policyMemberSlot must locate the bool flag set by updateAllowlist"
        );
    }

    /// @notice Verifies `policyMemberSlot` slots are disjoint across (id, account) pairs.
    /// @dev    Different ids OR different accounts must derive disjoint slots.
    function test_policyMemberSlot_success_disjointAcrossKeys(uint64 idA, uint64 idB, address accA, address accB)
        public
        pure
    {
        // Exercise the path where at least one key differs.
        vm.assume(idA != idB || accA != accB);

        assertTrue(
            MockPolicyRegistryStorage.policyMemberSlot(idA, accA)
                != MockPolicyRegistryStorage.policyMemberSlot(idB, accB),
            "policyMemberSlot must differ when (id, account) differs"
        );
    }

    /// @notice Verifies `pendingAdminSlot(id)` locates the staged-admin
    ///         slot `stageUpdateAdmin` writes.
    /// @dev    Stage a transfer, then read the helper-derived slot.
    function test_pendingAdminSlot_success_locatesStagedAdmin(address policyAdmin, address pending) public {
        vm.assume(policyAdmin != address(0));
        vm.assume(pending != address(0));
        vm.assume(pending != policyAdmin);

        uint64 policyId = _createAllowlist(admin, policyAdmin);

        vm.prank(policyAdmin);
        policyRegistry.stageUpdateAdmin(policyId, pending);

        assertEq(
            address(
                uint160(uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.pendingAdminSlot(policyId))))
            ),
            pending,
            "pendingAdminSlot must locate the staged admin"
        );
    }

    /// @notice Verifies `nextCounterSlot()` advances by exactly 1 per
    ///         createPolicy in the steady state.
    /// @dev    The very first `createPolicy` also lazily writes the two
    ///         built-in policies, advancing the counter from 0 to
    ///         `BUILTIN_POLICY_COUNT` before consuming a slot for the new
    ///         policy (so the apparent delta is `BUILTIN_POLICY_COUNT + 1`).
    ///         Pre-create to clear init, then measure the steady-state delta.
    function test_nextCounterSlot_success_advancesByOneOnCreate(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        // Pre-create to clear the lazy init.
        _createAllowlist(admin, policyAdmin);

        uint256 before = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot()));
        _createAllowlist(admin, policyAdmin);
        uint256 after_ = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot()));

        assertEq(after_, before + 1, "subsequent createPolicy must bump nextCounter by exactly 1");
    }

    /// @notice Verifies `packPolicy` round-trips admin and sets the exists bit.
    function test_packPolicy_success_roundtrips(address policyAdmin) public pure {
        uint256 packed = MockPolicyRegistryStorage.packPolicy(policyAdmin);
        assertEq(MockPolicyRegistryStorage.policyAdminFromPacked(packed), policyAdmin, "admin round-trip");
        assertTrue(MockPolicyRegistryStorage.policyExistsFromPacked(packed), "exists bit must be set by packPolicy");
    }

    /// @notice Verifies `packPolicyId` is the inverse of the
    ///         policyType/counter ID decoders.
    /// @dev    Round-trip: pack the ID, decode each part, expect inputs back.
    function test_packPolicyId_success_roundtrips(uint8 policyType, uint56 counter) public pure {
        uint64 id = MockPolicyRegistryStorage.packPolicyId(policyType, counter);
        assertEq(MockPolicyRegistryStorage.policyTypeFromId(id), policyType, "type round-trip");
        assertEq(uint256(MockPolicyRegistryStorage.policyCounterFromId(id)), uint256(counter), "counter round-trip");
    }

    /// @notice Verifies the policy-ID layout matches the documented schema.
    /// @dev    A real createPolicy yields an ID whose top byte equals the
    ///         enum value of the policy type passed in (ALLOWLIST = 1,
    ///         BLOCKLIST = 0).
    function test_policyTypeFromId_success_decodesCreatePolicyResult(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        uint64 allowlistId = _createAllowlist(admin, policyAdmin);
        assertEq(
            MockPolicyRegistryStorage.policyTypeFromId(allowlistId),
            uint8(IPolicyRegistry.PolicyType.ALLOWLIST),
            "createPolicy(ALLOWLIST) must yield an ID whose type byte is ALLOWLIST"
        );

        uint64 blocklistId = _createBlocklist(admin, policyAdmin);
        assertEq(
            MockPolicyRegistryStorage.policyTypeFromId(blocklistId),
            uint8(IPolicyRegistry.PolicyType.BLOCKLIST),
            "createPolicy(BLOCKLIST) must yield an ID whose type byte is BLOCKLIST"
        );
    }
}
