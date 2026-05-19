// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {MockActivationRegistry} from "test/lib/mocks/MockActivationRegistry.sol";
import {MockPolicyRegistry} from "test/lib/mocks/MockPolicyRegistry.sol";
import {MockTokenFactory} from "test/lib/mocks/MockTokenFactory.sol";

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
/// built-in sentinel IDs `0` / `type(uint64).max` to exercise both
/// authorize and forbid paths without any custom registry state).
/// Centralizing the etch here means concrete bases don't need to
/// reason about which precompiles they "depend on" — they're all just
/// available, the way the EVM has `SLOAD`.
///
/// **Mock status.** The placeholder mocks etched here implement the
/// minimum needed for `setUp` to succeed across every base:
///   - `MockTokenFactory` implements the address-derivation schema so
///     `_deployToken` calls return real-shaped addresses.
///   - `MockPolicyRegistry` implements the two built-in sentinel IDs
///     (`0` → always-allow, `type(uint64).max` → always-reject).
///   - `MockActivationRegistry` implements `admin()` to return the
///     hardcoded test admin.
/// Every other method reverts with `"MockX: not implemented"`. Real
/// behavior fills in alongside test implementations in the next PR.
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
}
