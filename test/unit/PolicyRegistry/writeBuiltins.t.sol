// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";
import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Tests for the lazy `writeBuiltins` initialization that mirrors
///         the Rust precompile's `PolicyRegistryStorage::write_builtins`.
/// @dev    The mock is etched into bare storage by `BaseTest.setUp`, so
///         every test in this contract starts with a `nextCounter` slot
///         of 0 and empty `policies` mappings.
contract PolicyRegistryWriteBuiltinsTest is PolicyRegistryTest {
    MockPolicyRegistry internal mock = MockPolicyRegistry(address(policyRegistry));

    /// @notice `writeBuiltins` writes both sentinel slots with a renounced
    ///         (zero) admin and the exists bit set.
    /// @dev    The packed encoding matches `MockPolicyRegistryStorage.packPolicy(address(0))`.
    function test_writeBuiltins_success_populatesSentinelSlots() public {
        mock.writeBuiltins();

        uint256 expectedBuiltin = MockPolicyRegistryStorage.packPolicy(address(0));
        assertEq(
            uint256(
                vm.load(
                    address(policyRegistry),
                    MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_ALLOW_ID)
                )
            ),
            expectedBuiltin,
            "policies[ALWAYS_ALLOW_ID] must be packed(address(0)) after writeBuiltins"
        );
        assertEq(
            uint256(
                vm.load(
                    address(policyRegistry),
                    MockPolicyRegistryStorage.policySlot(PolicyRegistryConstants.ALWAYS_BLOCK_ID)
                )
            ),
            expectedBuiltin,
            "policies[ALWAYS_BLOCK_ID] must be packed(address(0)) after writeBuiltins"
        );
    }

    /// @notice `writeBuiltins` advances `nextCounter` from 0 to `BUILTIN_POLICY_COUNT`.
    function test_writeBuiltins_success_advancesCounterToBuiltinCount() public {
        mock.writeBuiltins();

        uint256 counter = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot()));
        assertEq(counter, uint256(mock.BUILTIN_POLICY_COUNT()), "nextCounter must equal BUILTIN_POLICY_COUNT");
    }

    /// @notice Repeated calls to `writeBuiltins` are a no-op: the counter
    ///         stays at `BUILTIN_POLICY_COUNT` regardless of call count.
    function test_writeBuiltins_success_idempotent() public {
        mock.writeBuiltins();
        mock.writeBuiltins();
        mock.writeBuiltins();

        uint256 counter = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot()));
        assertEq(counter, uint256(mock.BUILTIN_POLICY_COUNT()), "nextCounter must remain at BUILTIN_POLICY_COUNT");
    }

    /// @notice The first `createPolicy` triggers `writeBuiltins` lazily.
    /// @dev    Before any create, the sentinel slots are empty (zero). After
    ///         a single custom create, both sentinel slots and the new
    ///         policy slot are all populated, and the counter equals
    ///         `BUILTIN_POLICY_COUNT + 1`.
    function test_writeBuiltins_success_calledLazilyOnFirstCreate(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        // Sanity: sentinel slots start empty.
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

        uint64 customId = _createAllowlist(admin, policyAdmin);

        // After lazy init, both sentinel slots carry the renounced-admin packed word.
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

        // The custom policy lands at counter == BUILTIN_POLICY_COUNT and
        // nextCounter advances by exactly one more.
        uint64 counterMask = (uint64(1) << 56) - 1;
        assertEq(
            uint256(customId & counterMask),
            uint256(mock.BUILTIN_POLICY_COUNT()),
            "first custom policy must use counter == BUILTIN_POLICY_COUNT"
        );
        assertEq(
            uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot())),
            uint256(mock.BUILTIN_POLICY_COUNT()) + 1,
            "nextCounter must equal BUILTIN_POLICY_COUNT + 1 after first custom create"
        );
    }

    /// @notice Once `writeBuiltins` has run (either explicitly or lazily),
    ///         the sentinel admin slots are zero and `policyAdmin` confirms
    ///         that via the normal storage path — no fast-path required.
    function test_writeBuiltins_success_sentinelAdminsReadAsZero() public {
        mock.writeBuiltins();
        assertEq(
            policyRegistry.policyAdmin(PolicyRegistryConstants.ALWAYS_ALLOW_ID),
            address(0),
            "policyAdmin(ALWAYS_ALLOW_ID) must be address(0) after writeBuiltins"
        );
        assertEq(
            policyRegistry.policyAdmin(PolicyRegistryConstants.ALWAYS_BLOCK_ID),
            address(0),
            "policyAdmin(ALWAYS_BLOCK_ID) must be address(0) after writeBuiltins"
        );
    }

    /// @notice `policyExists` returns `true` for the built-in IDs before
    ///         `writeBuiltins` has run, via the dedicated fast-path.
    /// @dev    Mirrors the Rust impl's pre-init fast-path: B-20 tokens and
    ///         other consumers may query the sentinel IDs before any
    ///         `createPolicy` has run.
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
