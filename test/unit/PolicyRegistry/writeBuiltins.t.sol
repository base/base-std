// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Tests for the lazy built-in-policy initialization that mirrors
///         the Rust precompile's `PolicyRegistryStorage::write_builtins`.
///
/// @dev    `write_builtins` is internal to the registry on both sides
///         (Rust: `pub` in-crate only, not in dispatch; Solidity: private
///         helper called by `_create`). These tests therefore exercise the
///         behavior only through the public `IPolicyRegistry` surface — the
///         same surface a live-precompile fork test reaches. The mock is
///         etched into bare storage by `BaseTest.setUp`, so every test
///         starts with a `nextCounter` slot of 0 and empty `policies`
///         mappings.
contract PolicyRegistryWriteBuiltinsTest is PolicyRegistryTest {
    /// @notice The first `createPolicy` writes both sentinel slots with a
    ///         renounced (zero) admin and the exists bit set.
    /// @dev    Asserts the storage layout the Rust impl must reproduce
    ///         byte-for-byte: `policies[ALWAYS_ALLOW_ID]` and
    ///         `policies[ALWAYS_BLOCK_ID]` are both `packPolicy(address(0))`.
    function test_writeBuiltins_success_firstCreatePopulatesSentinelSlots(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        // Sanity: sentinel slots start empty before any create.
        assertEq(
            vm.load(
                address(policyRegistry), MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_ALLOW_ID)
            ),
            bytes32(0),
            "ALWAYS_ALLOW_ID slot must be empty before init"
        );
        assertEq(
            vm.load(
                address(policyRegistry), MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_BLOCK_ID)
            ),
            bytes32(0),
            "ALWAYS_BLOCK_ID slot must be empty before init"
        );

        _createAllowlist(admin, policyAdmin);

        uint256 expectedBuiltin = MockPolicyRegistryStorage.packPolicy(address(0));
        assertEq(
            uint256(
                vm.load(
                    address(policyRegistry),
                    MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_ALLOW_ID)
                )
            ),
            expectedBuiltin,
            "ALWAYS_ALLOW_ID slot must be populated by lazy init"
        );
        assertEq(
            uint256(
                vm.load(
                    address(policyRegistry),
                    MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_BLOCK_ID)
                )
            ),
            expectedBuiltin,
            "ALWAYS_BLOCK_ID slot must be populated by lazy init"
        );
    }

    /// @notice The first custom policy lands at counter `BUILTIN_POLICY_COUNT`
    ///         and `nextCounter` advances to `BUILTIN_POLICY_COUNT + 1`.
    /// @dev    Confirms the sentinels are NOT skipped via a runtime floor —
    ///         they actually consume counter slots 0 and 1 via init.
    function test_writeBuiltins_success_firstCustomPolicyAtBuiltinCount(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        uint64 customId = _createAllowlist(admin, policyAdmin);

        uint64 counterMask = (uint64(1) << 56) - 1;
        assertEq(
            uint256(customId & counterMask),
            uint256(PolicyRegistryConstants.BUILTIN_POLICY_COUNT),
            "first custom policy must use counter == BUILTIN_POLICY_COUNT"
        );
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())),
            uint256(PolicyRegistryConstants.BUILTIN_POLICY_COUNT) + 1,
            "nextCounter must equal BUILTIN_POLICY_COUNT + 1 after first custom create"
        );
    }

    /// @notice Lazy init runs at most once: subsequent `createPolicy` calls
    ///         each advance `nextCounter` by exactly 1.
    /// @dev    Idempotence of the init via the public surface — guards
    ///         against a regression where re-running init would overwrite
    ///         sentinel slots or double-bump the counter.
    function test_writeBuiltins_success_lazyInitIdempotent(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        _createAllowlist(admin, policyAdmin);
        _createAllowlist(admin, policyAdmin);
        _createAllowlist(admin, policyAdmin);

        // Three custom creates after init: counter = BUILTIN_POLICY_COUNT + 3.
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())),
            uint256(PolicyRegistryConstants.BUILTIN_POLICY_COUNT) + 3,
            "nextCounter must advance by exactly 1 per createPolicy after init"
        );

        // Sentinel slots still hold the original packed-zero word — not
        // overwritten by re-entrant init attempts.
        uint256 expectedBuiltin = MockPolicyRegistryStorage.packPolicy(address(0));
        assertEq(
            uint256(
                vm.load(
                    address(policyRegistry),
                    MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_ALLOW_ID)
                )
            ),
            expectedBuiltin,
            "ALWAYS_ALLOW_ID slot must survive subsequent inits"
        );
        assertEq(
            uint256(
                vm.load(
                    address(policyRegistry),
                    MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_BLOCK_ID)
                )
            ),
            expectedBuiltin,
            "ALWAYS_BLOCK_ID slot must survive subsequent inits"
        );
    }

    /// @notice Once init has run (via any `createPolicy`), `policyAdmin` for
    ///         the sentinels returns `address(0)` via the normal storage
    ///         read — no built-in fast path required.
    function test_writeBuiltins_success_sentinelAdminsReadAsZeroAfterInit(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        _createAllowlist(admin, policyAdmin);

        assertEq(
            policyRegistry.policyAdmin(PolicyRegistryConstants.ALWAYS_ALLOW_ID),
            address(0),
            "policyAdmin(ALWAYS_ALLOW_ID) must be address(0) after init"
        );
        assertEq(
            policyRegistry.policyAdmin(PolicyRegistryConstants.ALWAYS_BLOCK_ID),
            address(0),
            "policyAdmin(ALWAYS_BLOCK_ID) must be address(0) after init"
        );
    }

    /// @notice `policyExists` returns `true` for the built-in IDs before any
    ///         `createPolicy` has been called, via the dedicated fast-path.
    /// @dev    Mirrors the Rust impl's pre-init fast-path: B-20 tokens and
    ///         other consumers may query the sentinel IDs before any
    ///         `createPolicy` has triggered init.
    function test_writeBuiltins_success_policyExistsFastPathPreInit() public view {
        assertTrue(
            policyRegistry.policyExists(PolicyRegistryConstants.ALWAYS_ALLOW_ID),
            "policyExists(ALWAYS_ALLOW_ID) must be true pre-init"
        );
        assertTrue(
            policyRegistry.policyExists(PolicyRegistryConstants.ALWAYS_BLOCK_ID),
            "policyExists(ALWAYS_BLOCK_ID) must be true pre-init"
        );
    }
}
