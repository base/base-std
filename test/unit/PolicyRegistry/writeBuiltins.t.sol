// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Tests for built-in sentinel policy initialization in `PolicyRegistry`.
///
/// @dev    `_writeBuiltins` is called eagerly inside `initialize()`, so the
///         sentinel slots are populated before any `createPolicy` call. These
///         tests exercise the initialized state through the public
///         `IPolicyRegistry` surface and confirm the underlying storage layout.
contract PolicyRegistryWriteBuiltinsTest is PolicyRegistryTest {
    /// @notice Both sentinel slots are populated with the expected packed value
    ///         immediately after `initialize()`.
    /// @dev    Asserts the storage layout: `policies[ALWAYS_ALLOW_ID]` and
    ///         `policies[ALWAYS_BLOCK_ID]` both encode a zero admin with the
    ///         exists bit set.
    function test_writeBuiltins_success_sentinelSlotsPopulatedOnInit() public view {
        uint256 expectedBuiltin = MockPolicyRegistryStorage.packPolicy(address(0));
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(ALWAYS_ALLOW_ID))),
            expectedBuiltin,
            "ALWAYS_ALLOW_ID slot must be populated after initialize"
        );
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(ALWAYS_BLOCK_ID))),
            expectedBuiltin,
            "ALWAYS_BLOCK_ID slot must be populated after initialize"
        );
    }

    /// @notice `nextCounter` starts at `BUILTIN_POLICY_COUNT` after initialize,
    ///         so the first custom policy lands at counter `BUILTIN_POLICY_COUNT`.
    function test_writeBuiltins_success_firstCustomPolicyAtBuiltinCount(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        uint64 customId = _createAllowlist(admin, policyAdmin);

        uint64 counterMask = (uint64(1) << 56) - 1;
        assertEq(
            uint256(customId & counterMask),
            uint256(BUILTIN_POLICY_COUNT),
            "first custom policy must use counter == BUILTIN_POLICY_COUNT"
        );
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())),
            uint256(BUILTIN_POLICY_COUNT) + 1,
            "nextCounter must equal BUILTIN_POLICY_COUNT + 1 after first custom create"
        );
    }

    /// @notice Subsequent `createPolicy` calls each advance `nextCounter` by
    ///         exactly 1, and sentinel slots are never overwritten.
    function test_writeBuiltins_success_sentinelSlotsPreservedAfterCreates(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        _createAllowlist(admin, policyAdmin);
        _createAllowlist(admin, policyAdmin);
        _createAllowlist(admin, policyAdmin);

        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())),
            uint256(BUILTIN_POLICY_COUNT) + 3,
            "nextCounter must advance by exactly 1 per createPolicy"
        );

        uint256 expectedBuiltin = MockPolicyRegistryStorage.packPolicy(address(0));
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(ALWAYS_ALLOW_ID))),
            expectedBuiltin,
            "ALWAYS_ALLOW_ID slot must be unchanged after subsequent creates"
        );
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(ALWAYS_BLOCK_ID))),
            expectedBuiltin,
            "ALWAYS_BLOCK_ID slot must be unchanged after subsequent creates"
        );
    }

    /// @notice `policyAdmin` returns `address(0)` for both sentinels.
    function test_writeBuiltins_success_sentinelAdminsAreZero() public view {
        assertEq(
            policyRegistry.policyAdmin(ALWAYS_ALLOW_ID), address(0), "policyAdmin(ALWAYS_ALLOW_ID) must be address(0)"
        );
        assertEq(
            policyRegistry.policyAdmin(ALWAYS_BLOCK_ID), address(0), "policyAdmin(ALWAYS_BLOCK_ID) must be address(0)"
        );
    }

    /// @notice `policyExists` returns `true` for both built-in sentinel IDs.
    function test_writeBuiltins_success_builtinPoliciesExist() public view {
        assertTrue(policyRegistry.policyExists(ALWAYS_ALLOW_ID), "policyExists(ALWAYS_ALLOW_ID) must be true");
        assertTrue(policyRegistry.policyExists(ALWAYS_BLOCK_ID), "policyExists(ALWAYS_BLOCK_ID) must be true");
    }
}
