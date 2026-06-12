// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";
import {MockActivationRegistry} from "base-std-test/lib/mocks/MockActivationRegistry.sol";
import {MockPolicyRegistry} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";
import {MockB20Factory} from "base-std-test/lib/mocks/MockB20Factory.sol";

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

/// @notice Common base for every test contract in this suite.
///
/// Owns the actors / labels and the precompile-mock etch wiring that
/// every concrete base would otherwise re-declare. Concrete bases
/// (`B20FactoryTest`, `PolicyRegistryTest`, ...) extend this and
/// layer on their own helpers and any test-class-specific state.
///
/// **Reference vs. live precompiles.** The suite runs in one of two
/// worlds, detected automatically (no flag to remember):
///   - **Reference mode** (stock `forge test`): the precompile
///     addresses are empty, so `setUp` etches the Solidity mocks — you
///     are testing the reference implementation itself.
///   - **Live precompile mode** (`base-forge test`, or `forge test
///     --fork-url <base-anvil node>`): base-anvil's `--base` mode makes
///     the real Rust precompiles present, so `setUp` skips the etch —
///     you are checking base/base against the reference (conformance).
///
/// Detection is a behavioral probe (STATICCALL `ActivationRegistry.admin()`
/// before any etch), not an `extcodesize` check: native precompiles
/// report zero code even when they respond to calls, so a code-size
/// check is unreliable and would silently clobber a live precompile
/// with a mock. `LIVE_PRECOMPILES=true` forces live mode as an escape
/// hatch. The detected world is recorded in `livePrecompiles` and
/// announced via a `setUp` log line.
///
/// **Cross-precompile dependency model.** Every test gets all three
/// precompile mocks etched. Token tests need the factory mock to
/// deploy a token, and need the policy-registry mock so the token's
/// cross-precompile `isAuthorized` calls don't hit empty code and
/// revert at the EVM level (the most common B20 policy tests use the
/// built-in sentinel IDs `PolicyRegistryConstants.ALWAYS_ALLOW_ID` and
/// `PolicyRegistryConstants.ALWAYS_BLOCK_ID` to exercise both authorize
/// and forbid paths without any custom registry state). Centralizing
/// the etch here means concrete bases don't need to
/// reason about which precompiles they "depend on" — they're all just
/// available, the way the EVM has `SLOAD`.
///
/// **Mock status.**
///   - `MockB20Factory` is fully implemented: `createToken` decodes
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
///     mutation, and admin rotation all work. Built-in IDs
///     `ALWAYS_ALLOW_ID = 0` and
///     `ALWAYS_BLOCK_ID = (uint64(ALLOWLIST) << 56) | 1` are
///     short-circuited before any storage read.
///   - `MockActivationRegistry` is fully implemented: every
///     `IActivationRegistry` surface function is live. `admin()` returns
///     the hardcoded `0xCB00…0000` address; `activate` / `deactivate`
///     mutate a single ERC-7201-namespaced `features` map and emit the
///     paired events. Only admin (resolved at setUp via
///     `activationRegistry.admin()`) may flip features.
abstract contract BaseTest is Test {
    // -- Actors --
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    /// @notice True when the live base/base precompiles are present
    ///         (`base-forge` / base-anvil), false when the Solidity mocks are
    ///         etched (stock `forge`). Set in setUp; read by tests that are
    ///         only meaningful in one world.
    bool internal livePrecompiles;

    // -- Setup --
    function setUp() public virtual {
        vm.label(admin, "admin");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(attacker, "attacker");

        vm.label(StdPrecompiles.B20_FACTORY_ADDRESS, "B20Factory");
        vm.label(StdPrecompiles.POLICY_REGISTRY_ADDRESS, "PolicyRegistry");
        vm.label(StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS, "ActivationRegistry");

        // Pick the world by detecting whether the live precompiles are
        // present (see contract NatSpec), then announce it so a run is never
        // ambiguous about what it validated.
        livePrecompiles = _detectLivePrecompiles();
        if (livePrecompiles) {
            console2.log("[base-std] LIVE PRECOMPILE mode: exercising base/base's precompiles (conformance check)");
            // The precompiles are present and base-anvil's --base mode seeds
            // their features, so there is nothing to etch or bootstrap.
            return;
        }

        console2.log("[base-std] REFERENCE mode: exercising the Solidity mocks; base/base is NOT under test");

        vm.etch(StdPrecompiles.B20_FACTORY_ADDRESS, type(MockB20Factory).runtimeCode);
        vm.etch(StdPrecompiles.POLICY_REGISTRY_ADDRESS, type(MockPolicyRegistry).runtimeCode);
        vm.etch(StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS, type(MockActivationRegistry).runtimeCode);

        // Activate every B-20 feature so the bulk of the suite — which
        // exercises behaviors orthogonal to the activation gate — doesn't
        // have to repeat the bootstrap. Tests that pin the gating behavior
        // itself (`B20Factory/activation.t.sol`) deactivate the specific
        // feature under test before exercising it.
        address activationAdmin = StdPrecompiles.ACTIVATION_REGISTRY.admin();
        vm.startPrank(activationAdmin);
        StdPrecompiles.ACTIVATION_REGISTRY.activate(ActivationRegistryFeatureList.B20_ASSET);
        StdPrecompiles.ACTIVATION_REGISTRY.activate(ActivationRegistryFeatureList.B20_STABLECOIN);
        StdPrecompiles.ACTIVATION_REGISTRY.activate(ActivationRegistryFeatureList.POLICY_REGISTRY);
        vm.stopPrank();
    }

    /// @notice Detect whether the live precompiles are present in this EVM.
    ///
    /// @dev Behavioral probe rather than `extcodesize`: native precompiles
    ///      report zero code even when they respond, so a code-size check is
    ///      unreliable. We STATICCALL `ActivationRegistry.admin()` before any
    ///      mock is etched — a live precompile returns a 32-byte address; an
    ///      empty address (stock forge) returns zero-length returndata.
    ///      `LIVE_PRECOMPILES=true` forces live as an escape hatch.
    function _detectLivePrecompiles() private view returns (bool) {
        if (vm.envOr("LIVE_PRECOMPILES", false)) return true;
        (bool ok, bytes memory ret) =
            StdPrecompiles.ACTIVATION_REGISTRY_ADDRESS.staticcall(abi.encodeCall(IActivationRegistry.admin, ()));
        return ok && ret.length >= 32;
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
        vm.assume(caller != StdPrecompiles.B20_FACTORY_ADDRESS);
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

    /// @notice True iff `policyId`'s top byte is in the `PolicyType` enum range.
    function _isWellFormedPolicyId(uint64 policyId) internal pure returns (bool) {
        return uint8(policyId >> 56) <= uint8(type(IPolicyRegistry.PolicyType).max);
    }

    /// @notice Maps a fuzz seed to a well-formed but uncreated `policyId`.
    ///         Top byte is forced into the `PolicyType` enum range; counter
    ///         is forced >= 2 to skip both sentinel counters.
    function _wellFormedUncreatedPolicyId(uint64 seed) internal pure returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 typeByte = uint8(seed % (uint64(type(IPolicyRegistry.PolicyType).max) + 1));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint56 counter = uint56((seed >> 8) | 2);
        return (uint64(typeByte) << 56) | uint64(counter);
    }

    /// @notice Maps a fuzz seed to a MALFORMED `policyId`: top byte is
    ///         forced above the `PolicyType` enum range. View queries
    ///         short-circuit these to the "absent" value; mutating calls
    ///         reject via `PolicyNotFound`.
    function _malformedPolicyId(uint64 seed) internal pure returns (uint64) {
        uint8 maxValidType = uint8(type(IPolicyRegistry.PolicyType).max);
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
    ///         Encoding (mirrors `MockB20Factory._writeString`):
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

    // ============================================================
    //                       LOG-ORDERING HELPER
    // ============================================================

    /// @notice Returns the index of the first log in `logs` whose
    ///         `topics[0]` equals `sig`, or `-1` if no matching log
    ///         exists (or the matching log is anonymous, i.e. has no
    ///         topics at all).
    /// @dev    Sentinel return is `-1` rather than `type(uint256).max`
    ///         so call sites can write `assertGt(idx, -1, "...")` to
    ///         assert presence and `assertLt(headerIdx, footerIdx, "...")`
    ///         to assert ordering, both as plain integer comparisons.
    ///         Tests that need to pin down emission ORDER (header before
    ///         footer, Transfer before Memo, etc.) call
    ///         this once per signature on a `vm.recordLogs()` capture
    ///         and compare the indices. Tests that just need to assert
    ///         a specific event was emitted should prefer
    ///         `vm.expectEmit` with `expectEmit + emit ... + call`.
    function _firstLogIndex(Vm.Log[] memory logs, bytes32 sig) internal pure returns (int256) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            // `i` is bounded by `logs.length`, which a forge fuzz run cannot push
            // anywhere near `int256.max`, so the cast cannot truncate.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (logs[i].topics[0] == sig) return int256(i);
        }
        return -1;
    }
}
