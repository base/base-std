// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {MockActivationRegistry} from "test/lib/mocks/MockActivationRegistry.sol";
import {MockPolicyRegistry} from "test/lib/mocks/MockPolicyRegistry.sol";
import {MockTokenFactory} from "test/lib/mocks/MockTokenFactory.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

/// @notice Common base for every test contract in this suite.
///
/// Owns the actors / labels and the precompile-mock etch wiring that
/// every concrete base would otherwise re-declare. Concrete bases
/// (`TokenFactoryTest`, `PolicyRegistryTest`, ...) extend this and
/// layer on their own helpers and any test-class-specific state.
///
/// **Mock-vs-live.** `setUp` etches each precompile mock at its
/// canonical address only when the address currently has no code. When
/// forking a node where the live precompile is already deployed, the
/// etch is skipped silently and the same test body executes against
/// the live impl. No env vars or flags — the fork URL alone selects
/// the backend.
///
/// **Cross-precompile dependency model.** Every test gets all three
/// precompile mocks etched. Token tests need the factory mock to
/// deploy a token, and need the policy-registry mock so the token's
/// cross-precompile `isAuthorized` calls don't hit empty code and
/// revert at the EVM level (the most common B20 policy tests use the
/// built-in sentinel IDs `0` (ALWAYS_ALLOW) and `1` (ALWAYS_BLOCK) to
/// exercise both authorize and forbid paths without any custom registry
/// state). Centralizing the etch here means concrete bases don't need to
/// reason about which precompiles they "depend on" — they're all just
/// available, the way the EVM has `SLOAD`.
///
/// **Mock status.**
///   - `MockTokenFactory` is fully implemented: `createToken` decodes
///     params, etches the variant-appropriate runtime bytecode at the
///     computed B-20 address, writes initial state directly via vm.store
///     (no init function on the token), runs initCalls, and closes the
///     privileged window before returning.
///   - `MockB20` / `MockB20Stablecoin` (planted by the factory at token
///     addresses) are fully implemented: every `IB20` / `IB20Stablecoin`
///     surface function is live, with the bootstrap-window auth bypass
///     for factory-originated calls and the standard role / policy /
///     pause / supply-cap checks otherwise.
///   - `MockPolicyRegistry` is fully implemented: every `IPolicyRegistry`
///     surface function is live. Custom policy creation, membership
///     mutation, and admin rotation all work. Built-in IDs `0`
///     (ALWAYS_ALLOW) and `1` (ALWAYS_BLOCK) are short-circuited before
///     any storage read.
///   - `MockActivationRegistry` is a SKELETON: implements only `admin()`
///     to return the hardcoded test admin.
abstract contract BaseTest is Test {
    // -- Actors --
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    // -- Setup --
    function setUp() public virtual {
        vm.label(admin, "admin");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(attacker, "attacker");

        vm.label(StdPrecompiles.TOKEN_FACTORY_ADDRESS, "TokenFactory");
        vm.label(StdPrecompiles.POLICY_REGISTRY_ADDRESS, "PolicyRegistry");
        vm.label(StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS, "ActivationRegistry");

        if (StdPrecompiles.TOKEN_FACTORY_ADDRESS.code.length == 0) {
            vm.etch(StdPrecompiles.TOKEN_FACTORY_ADDRESS, type(MockTokenFactory).runtimeCode);
        }
        if (StdPrecompiles.POLICY_REGISTRY_ADDRESS.code.length == 0) {
            vm.etch(StdPrecompiles.POLICY_REGISTRY_ADDRESS, type(MockPolicyRegistry).runtimeCode);
        }
        if (StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS.code.length == 0) {
            vm.etch(StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS, type(MockActivationRegistry).runtimeCode);
        }
    }

    /// @notice Filters out addresses that are unsafe to use as a fuzzed
    ///         `msg.sender` in test bodies.
    ///
    /// Pranking these addresses produces meaningless or misleading test
    /// outcomes:
    ///   - `address(0)`: many functions revert specifically on zero
    ///     sender (`InvalidSender`, `InvalidApprover`), masking the
    ///     behavior under test.
    ///   - The forge-std VM cheatcode address: pranking it disrupts
    ///     subsequent cheatcode calls.
    ///   - Any of the etched precompiles: they have a privileged
    ///     auth-bypass path (e.g. `MockB20`'s factory bootstrap window),
    ///     so calls "from" them go through a different code path than
    ///     a user would.
    function _assumeValidCaller(address caller) internal pure {
        vm.assume(caller != address(0));
        vm.assume(caller != address(vm));
        vm.assume(caller != StdPrecompiles.TOKEN_FACTORY_ADDRESS);
        vm.assume(caller != StdPrecompiles.POLICY_REGISTRY_ADDRESS);
        vm.assume(caller != StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS);
    }

    // ============================================================
    //                  POLICY-ID ENCODING HELPERS
    // ============================================================
    // The registry validates the policyId encoding (top byte must be
    // a valid `PolicyType` discriminator) before any other check, so
    // tests fuzzing arbitrary uint64s need to partition their inputs
    // into well-formed and malformed regions to assert the right error.

    /// @notice True iff `policyId`'s top byte (the PolicyType
    ///         discriminator) is in the valid `PolicyType` enum range.
    function _isWellFormedPolicyId(uint64 policyId) internal pure returns (bool) {
        return uint8(policyId >> 56) <= uint8(IPolicyRegistry.PolicyType.BLOCKLIST);
    }

    /// @notice Maps a fuzz seed to a well-formed but uncreated `policyId`.
    ///         Top byte is forced into `{ALLOWLIST, BLOCKLIST}` (custom
    ///         range, never sentinel) and low 56 bits are forced strictly
    ///         above the sentinel range so the ID can never collide with
    ///         a sentinel or with any policy a registry could create from
    ///         a fresh state.
    function _wellFormedUncreatedPolicyId(uint64 seed) internal pure returns (uint64) {
        uint8 typeByte = uint8(IPolicyRegistry.PolicyType.ALLOWLIST) + uint8(seed % 2);
        // Use bits [62:8] as the counter source so the top byte and the
        // counter selection are independent. Force counter >= 2 to skip
        // both sentinel IDs (0 and 1).
        uint56 counter = uint56((seed >> 8) | 2);
        return (uint64(typeByte) << 56) | uint64(counter);
    }

    /// @notice Maps a fuzz seed to a MALFORMED `policyId`: top byte is
    ///         forced strictly above the `PolicyType` enum range so the
    ///         registry rejects it with `MalformedPolicyId`.
    function _malformedPolicyId(uint64 seed) internal pure returns (uint64) {
        uint8 maxValidType = uint8(IPolicyRegistry.PolicyType.BLOCKLIST);
        uint8 invalidRange = type(uint8).max - maxValidType;
        uint8 typeByte = maxValidType + 1 + uint8(seed % invalidRange);
        return (uint64(typeByte) << 56) | uint64(seed & ((1 << 56) - 1));
    }

    // ============================================================
    //                  STRING SLOT ENCODING HELPER
    // ============================================================

    /// @notice Returns the bytes32 value Solidity stores in a `string`
    ///         field's slot for `value`, per the short/long encoding
    ///         convention.
    /// @dev    Used by slot-augmented tests that write strings
    ///         (`name` / `symbol` / `contractURI` / `currency`) to
    ///         verify the field slot reflects the written value
    ///         byte-for-byte. This is the storage contract the Rust
    ///         precompile impl must match exactly.
    ///
    ///         Encoding (mirrors `MockTokenFactory._writeString`):
    ///         - Empty string: slot is zero.
    ///         - Length < 32: high portion holds the bytes (left-justified
    ///           in the slot); low byte is `length * 2` (low bit clear).
    ///         - Length >= 32: slot holds `length * 2 + 1` (low bit set);
    ///           data lives at `keccak256(slot)` onwards. This helper
    ///           returns the FIELD slot value only; long-string body
    ///           assertions are done separately at the data offset.
    function _expectedStringFieldSlot(string memory value) internal pure returns (bytes32) {
        bytes memory data = bytes(value);
        if (data.length == 0) return bytes32(0);
        if (data.length < 32) {
            bytes32 highPortion;
            assembly {
                highPortion := mload(add(data, 32))
            }
            return bytes32(uint256(highPortion) | (data.length * 2));
        }
        return bytes32(data.length * 2 + 1);
    }
}
