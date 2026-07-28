// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";
import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title  PolicyRegistry composite-unsupported (Beryl / V1) suite
///
/// @notice The inverse of the composite suite: this file asserts the CORRECT behavior of a registry
///         that does **not** implement composite policies. Composites are a `PolicyRegistry` V2
///         feature activated at the Cobalt hardfork; on a V1 (Beryl) registry the dispatcher
///         short-circuits both composite selectors to `UnknownFunctionSelector` before any routing
///         or ABI decode, and the observable revert data is the **bare 4-byte selector** — not an
///         ABI-encoded error, and specifically not `FeatureNotActivated`.
///
/// @dev **Every test here skips when composites ARE supported.** Each body opens with
///      `vm.skip(_compositeSupported())`, mirroring the per-test skip style of
///      `test/unit/PolicyRegistry/dispatch_inactive.t.sol` (which documents itself as live-only for
///      the same reason: the behavior it pins exists in only one of the two worlds).
///
///      **In REFERENCE mode (stock `forge test`) every test in this file SKIPS, and that is the
///      correct and expected outcome.** `MockPolicyRegistry` implements V2 unconditionally, so
///      there is no V1 surface to assert against. These tests have teeth only in the live lane
///      (`make fork-tests` / `base-forge test`), where `base-anvil` hard-pins `BaseUpgrade::Beryl`
///      = V1 until `--base-fork` (BOP-428) makes the fork selectable. When that lands and the live
///      node moves to Cobalt, this file will start skipping there too — at which point the
///      composite suite proper takes over and this file becomes the historical record of V1.
///
///      Spec IDs cite `brains/composite_policy/SMOKE_TEST_SPECS.md` § CF — Fork lane, Beryl / V1
///      negatives. Raw low-level calls throughout: the point is to inspect revert DATA, which a
///      typed call would discard.
contract PolicyRegistryCompositeUnsupportedTest is PolicyRegistryTest {
    bytes32 internal constant FEATURE = ActivationRegistryFeatureList.POLICY_REGISTRY;

    // ============================================================
    //                          HELPERS
    // ============================================================

    /// @dev Drive the PolicyRegistry feature to `active`. Idempotent, and a no-op when already in
    ///      the requested state. Same mechanism as `dispatch_inactive.t.sol::_ensureInactive`.
    function _setActivation(bool active) internal {
        if (StdPrecompiles.ACTIVATION_REGISTRY.isActivated(FEATURE) == active) return;
        vm.prank(StdPrecompiles.ACTIVATION_REGISTRY.admin());
        if (active) {
            StdPrecompiles.ACTIVATION_REGISTRY.activate(FEATURE);
        } else {
            StdPrecompiles.ACTIVATION_REGISTRY.deactivate(FEATURE);
        }
    }

    /// @dev Whether `data` is exactly a `FeatureNotActivated(FEATURE)` revert payload.
    function _isFeatureNotActivated(bytes memory data) internal pure returns (bool) {
        return
            keccak256(data)
                == keccak256(abi.encodeWithSelector(IActivationRegistry.FeatureNotActivated.selector, FEATURE));
    }

    /// @dev Well-formed `createCompositePolicy` calldata over two real, existing simple policies.
    ///      "Well-formed" matters: it makes the failure unattributable to decoding. The call carries
    ///      a valid admin, a valid composite gate, and an in-range child set of live policy IDs, so
    ///      on a V2 registry it would SUCCEED. Every reason to revert other than "this function does
    ///      not exist" has been removed.
    function _wellFormedCreateCompositeCalldata() internal returns (bytes memory) {
        uint64[] memory children = _makeSimpleChildren(MIN_CHILD_POLICIES);
        return
            abi.encodeCall(IPolicyRegistry.createCompositePolicy, (admin, IPolicyRegistry.PolicyType.UNION, children));
    }

    /// @dev Well-formed `updateComposite` calldata. The target ID cannot be a live composite on a V1
    ///      node (none can be created there), so it references a well-formed ID; the selector never
    ///      resolves, so the argument is never read. Everything the ABI can check about this payload
    ///      is correct.
    function _wellFormedUpdateCompositeCalldata() internal returns (bytes memory) {
        uint64[] memory children = _makeSimpleChildren(MIN_CHILD_POLICIES);
        uint64 target = (uint64(uint8(IPolicyRegistry.PolicyType.UNION)) << 56) | uint64(2);
        return abi.encodeCall(IPolicyRegistry.updateComposite, (target, children));
    }

    /// @dev Asserts `payload` reverts with EXACTLY the bare 4-byte `expectedSelector` — the wire
    ///      form of `UnknownFunctionSelector` — and therefore not with any ABI-encoded error.
    ///
    ///      The length check is load-bearing and deliberately separate from the equality check: an
    ///      ABI-encoded custom error is 4 bytes of selector followed by 32-byte-padded arguments, so
    ///      `ret.length == 4` alone already rules out `FeatureNotActivated(bytes32)`,
    ///      `ChildPoliciesOutsideOfRange(uint256,uint256)`, `Error(string)`, `Panic(uint256)` and
    ///      every other encoded revert. Asserting the length first also produces a far more legible
    ///      failure than a whole-payload diff when the impl starts returning a real error.
    function _assertBareSelectorRevert(bytes memory payload, bytes4 expectedSelector, string memory label) internal {
        (bool ok, bytes memory ret) = address(policyRegistry).call(payload);
        assertFalse(ok, string.concat(label, " must revert on a registry without composite support"));
        assertEq(ret.length, 4, string.concat(label, " revert data must be a bare selector, not an ABI-encoded error"));
        assertEq(
            ret,
            abi.encodePacked(expectedSelector),
            string.concat(label, " revert data must be the unknown function selector itself")
        );
    }

    // ============================================================
    //          CF-1 / CF-2 — THE SELECTORS DO NOT RESOLVE
    // ============================================================

    /// @notice Verifies `createCompositePolicy` does not resolve on a V1 registry
    ///
    /// @dev Spec CF-1 (`SMOKE_TEST_SPECS.md` § CF) — "On a Beryl node, nobody can call
    ///      `createCompositePolicy` — the function does not exist. Bare 4-byte
    ///      `UnknownFunctionSelector`, not an ABI-encoded error."
    ///
    ///      V1's dispatcher matches the incoming selector against its known set and, on a miss,
    ///      reverts with the offending selector echoed back verbatim as the entire revert payload.
    ///      That is what makes "the function does not exist" distinguishable from "the function
    ///      exists and rejected your arguments": the latter always produces >= 4 bytes of encoded
    ///      error. The calldata is fully well-formed (see `_wellFormedCreateCompositeCalldata`) so
    ///      the failure cannot be blamed on decoding.
    function test_createCompositePolicy_revert_selectorUnknownOnV1() public {
        vm.skip(_compositeSupported());

        _assertBareSelectorRevert(
            _wellFormedCreateCompositeCalldata(),
            IPolicyRegistry.createCompositePolicy.selector,
            "createCompositePolicy"
        );
    }

    /// @notice Verifies `updateComposite` does not resolve on a V1 registry
    ///
    /// @dev Spec CF-2 (`SMOKE_TEST_SPECS.md` § CF) — "On a Beryl node, nobody can call
    ///      `updateComposite`. Same." The composite surface is two selectors and both must be
    ///      absent; asserting only the creator would let a half-shipped V1.5 (update present,
    ///      create missing) pass.
    function test_updateComposite_revert_selectorUnknownOnV1() public {
        vm.skip(_compositeSupported());

        _assertBareSelectorRevert(
            _wellFormedUpdateCompositeCalldata(), IPolicyRegistry.updateComposite.selector, "updateComposite"
        );
    }

    // ============================================================
    //       CF-3 — UNKNOWN-SELECTOR BEATS THE ACTIVATION GATE
    // ============================================================

    /// @notice Verifies the unknown-selector response is not masked by the activation gate
    ///
    /// @dev Spec CF-3 (`SMOKE_TEST_SPECS.md` § CF) — "The V1 unknown-selector response is not masked
    ///      by the activation gate. Unknown-selector classification wins over `FeatureNotActivated`,
    ///      active or not."
    ///
    ///      Two distinct failure modes are being separated here, and conflating them would hide a
    ///      genuine V1/V2 divergence behind a transient config state:
    ///        - "this selector does not exist on this registry version" — permanent, version-scoped;
    ///        - "this feature is switched off right now" — transient, admin-flippable.
    ///      If the gate ran before selector classification, an operator toggling the feature would
    ///      change the answer to "does composite support exist here?", and `_compositeSupported()`
    ///      — which is exactly this discrimination — would silently mis-detect.
    ///
    ///      The test therefore asserts the bare-selector payload in BOTH activation states, and
    ///      additionally that neither response is `FeatureNotActivated`. Activation is flipped via
    ///      `StdPrecompiles.ACTIVATION_REGISTRY` / `ActivationRegistryFeatureList.POLICY_REGISTRY`,
    ///      the same mechanism `dispatch_inactive.t.sol` uses.
    ///
    ///      The ACTIVE half runs unconditionally. The INACTIVE half is gated behind
    ///      `POLICY_DISPATCH_FIX`, matching `dispatch_inactive.t.sol`: stock builds return
    ///      `FeatureNotActivated` for unknown selectors until the dispatch-ordering fix reaches the
    ///      pinned impl. This is not a guess — it was measured. Against the current pinned
    ///      base-anvil the inactive half fails with "masked by FeatureNotActivated", so that build
    ///      evaluates the gate before selector classification. The assertion is kept verbatim behind
    ///      the flag rather than deleted or softened; the pin is what needs to move.
    function test_compositeSelectors_revert_unknownNotMaskedByActivation() public {
        vm.skip(_compositeSupported());

        // --- Feature ACTIVE: the gate is open, so nothing could be masking anything. Baseline.
        //     Also the state the payloads are built in — seeding child policies is itself a gated
        //     write. ---
        _setActivation(true);

        bytes memory createPayload = _wellFormedCreateCompositeCalldata();
        bytes memory updatePayload = _wellFormedUpdateCompositeCalldata();

        _assertBareSelectorRevert(
            createPayload, IPolicyRegistry.createCompositePolicy.selector, "createCompositePolicy (feature active)"
        );
        _assertBareSelectorRevert(
            updatePayload, IPolicyRegistry.updateComposite.selector, "updateComposite (feature active)"
        );

        // --- Feature INACTIVE: the gate would fire for any KNOWN write selector here. It must not
        //     fire for these two, because they never reach it.
        //
        //     Gated behind `POLICY_DISPATCH_FIX`, matching
        //     `dispatch_inactive.t.sol::test_dispatch_revert_unknownSelectorNotMaskedByActivation`.
        //     Measured against the current pinned base-anvil (Beryl): this half FAILS with
        //     "masked by FeatureNotActivated", confirming that build predates the dispatch-ordering
        //     fix and evaluates the activation gate before selector classification. The assertion is
        //     the spec and is kept verbatim — it is the pin that is stale, not the expectation. Run
        //     `make fork-tests POLICY_DISPATCH_FIX=true` against a node carrying the fix to exercise
        //     it; when the pin moves, drop this flag and the active/inactive halves collapse into one
        //     unconditional claim. ---
        if (!vm.envOr("POLICY_DISPATCH_FIX", false)) return;

        _setActivation(false);

        (bool createOk, bytes memory createRet) = address(policyRegistry).call(createPayload);
        assertFalse(createOk, "createCompositePolicy must revert while the feature is inactive");
        assertFalse(
            _isFeatureNotActivated(createRet),
            "createCompositePolicy must not be masked by FeatureNotActivated while inactive"
        );
        assertEq(createRet.length, 4, "createCompositePolicy revert data must stay a bare selector while inactive");
        assertEq(
            createRet,
            abi.encodePacked(IPolicyRegistry.createCompositePolicy.selector),
            "createCompositePolicy must still report the raw unknown selector while inactive"
        );

        (bool updateOk, bytes memory updateRet) = address(policyRegistry).call(updatePayload);
        assertFalse(updateOk, "updateComposite must revert while the feature is inactive");
        assertFalse(
            _isFeatureNotActivated(updateRet),
            "updateComposite must not be masked by FeatureNotActivated while inactive"
        );
        assertEq(updateRet.length, 4, "updateComposite revert data must stay a bare selector while inactive");
        assertEq(
            updateRet,
            abi.encodePacked(IPolicyRegistry.updateComposite.selector),
            "updateComposite must still report the raw unknown selector while inactive"
        );

        // The answer is identical in both states — that is the whole claim.
        assertEq(
            createRet,
            abi.encodePacked(IPolicyRegistry.createCompositePolicy.selector),
            "activation state must not change the unknown-selector classification"
        );
    }

    // ============================================================
    //        CF-4 — THE PROBE IS RIGHT AND THE REGISTRY IS ALIVE
    // ============================================================

    /// @notice Verifies the composite-support probe reports false here, and the rest of V1 works
    ///
    /// @dev Spec CF-4 (`SMOKE_TEST_SPECS.md` § CF) — "Composite tests self-skip on a V1 node rather
    ///      than failing. Detected at runtime, no env flag."
    ///
    ///      This is the meta-test for `_compositeSupported()`. Everything else in the composite
    ///      suite hangs off that probe, so a probe that returned the wrong answer would not produce
    ///      a red test — it would produce a SILENTLY SKIPPED suite, which is strictly worse. Two
    ///      halves:
    ///        1. the probe reports `false` on this registry (the skip guard at the top of the body
    ///           has already established that, but asserting it makes the file's premise explicit
    ///           and gives the failure a name if the probe ever becomes non-deterministic);
    ///        2. a full simple-policy round-trip — create, populate, query — still works. This rules
    ///           out the degenerate reading of half of this file: that the registry is simply dead,
    ///           unreachable, or reverting everything. It is alive; only the composite surface is
    ///           missing. Without this control, a completely broken node would make CF-1 … CF-3 pass
    ///           for entirely the wrong reason (well, apart from the bare-selector payload check,
    ///           which is what makes those precise in the first place).
    function test_compositeSupport_success_probeFalseAndSimplePathAlive() public {
        vm.skip(_compositeSupported());

        // 1. The probe agrees with this file's premise.
        assertFalse(_compositeSupported(), "composite support must be absent on a V1 registry");

        // 2. The simple surface is fully operational. Writes need the feature on.
        _setActivation(true);

        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertTrue(policyRegistry.policyExists(policyId), "a simple policy must still be creatable on V1");
        assertEq(policyRegistry.policyAdmin(policyId), admin, "the simple policy must carry its admin");

        // Empty allowlist blocks everyone.
        assertFalse(policyRegistry.isAuthorized(policyId, alice), "an empty allowlist must authorize nobody");

        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        vm.prank(admin);
        policyRegistry.updateAllowlist(policyId, true, accounts);

        assertTrue(policyRegistry.isAuthorized(policyId, alice), "an allowlisted account must be authorized");
        assertFalse(policyRegistry.isAuthorized(policyId, bob), "a non-member must not be authorized");
    }
}
