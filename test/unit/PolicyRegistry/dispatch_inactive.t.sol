// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";
import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";

/// @title PolicyRegistry dispatch tests for the inactive-feature path.
///
/// @notice PolicyRegistry error semantics must not depend on activation state: while inactive,
///         views stay callable and reach decode, writes stay gated, and an unknown selector is
///         classified rather than masked by `FeatureNotActivated`.
///
/// @dev Fork-only: `MockPolicyRegistry` models no activation gate, so this path exists only on the
///      live precompile. Each test skips unless `LIVE_PRECOMPILES` is set and normalizes the feature
///      to inactive first. Raw calls are used where the case needs malformed/unknown calldata.
contract PolicyRegistryDispatchInactiveTest is PolicyRegistryTest {
    bytes32 internal constant FEATURE = ActivationRegistryFeatureList.POLICY_REGISTRY;

    function _forkMode() internal view returns (bool) {
        return vm.envOr("LIVE_PRECOMPILES", false);
    }

    /// @dev Deactivate the feature if active; no-op otherwise (idempotent across both run modes).
    function _ensureInactive() internal {
        if (StdPrecompiles.ACTIVATION_REGISTRY.isActivated(FEATURE)) {
            vm.prank(StdPrecompiles.ACTIVATION_REGISTRY.admin());
            StdPrecompiles.ACTIVATION_REGISTRY.deactivate(FEATURE);
        }
    }

    /// @dev Whether `data` is exactly a `FeatureNotActivated(FEATURE)` revert payload.
    function _isFeatureNotActivated(bytes memory data) internal pure returns (bool) {
        return
            keccak256(data)
                == keccak256(abi.encodeWithSelector(IActivationRegistry.FeatureNotActivated.selector, FEATURE));
    }

    function _viewSelectors() internal pure returns (bytes4[4] memory) {
        return [
            IPolicyRegistry.isAuthorized.selector,
            IPolicyRegistry.policyExists.selector,
            IPolicyRegistry.policyAdmin.selector,
            IPolicyRegistry.pendingPolicyAdmin.selector
        ];
    }

    function _writeSelectors() internal pure returns (bytes4[7] memory) {
        return [
            IPolicyRegistry.createPolicy.selector,
            IPolicyRegistry.createPolicyWithAccounts.selector,
            IPolicyRegistry.stageUpdateAdmin.selector,
            IPolicyRegistry.finalizeUpdateAdmin.selector,
            IPolicyRegistry.renounceAdmin.selector,
            IPolicyRegistry.updateAllowlist.selector,
            IPolicyRegistry.updateBlocklist.selector
        ];
    }

    function _isKnownSelector(bytes4 selector) internal pure returns (bool) {
        bytes4[4] memory views = _viewSelectors();
        for (uint256 i = 0; i < views.length; i++) {
            if (selector == views[i]) return true;
        }
        bytes4[7] memory writes = _writeSelectors();
        for (uint256 i = 0; i < writes.length; i++) {
            if (selector == writes[i]) return true;
        }
        return false;
    }

    /// @notice Views stay callable while inactive.
    function test_dispatch_success_viewsCallableWhileInactive(uint64 policyId, address account) public {
        vm.skip(!_forkMode());
        _ensureInactive();

        policyRegistry.isAuthorized(policyId, account);
        policyRegistry.policyExists(policyId);
        policyRegistry.policyAdmin(policyId);
        policyRegistry.pendingPolicyAdmin(policyId);
    }

    /// @notice An unknown selector is classified, not masked by the activation gate.
    /// @dev Gated behind `POLICY_DISPATCH_FIX`: stock builds still return `FeatureNotActivated` here
    ///      until the dispatch-ordering fix is in the pinned impl.
    function test_dispatch_revert_unknownSelectorNotMaskedByActivation(bytes4 selector) public {
        vm.skip(!(_forkMode() && vm.envOr("POLICY_DISPATCH_FIX", false)));
        vm.assume(!_isKnownSelector(selector));
        _ensureInactive();

        (bool ok, bytes memory ret) = StdPrecompiles.POLICY_REGISTRY_ADDRESS.staticcall(abi.encodePacked(selector));
        assertFalse(ok, "unknown selector must revert");
        assertFalse(_isFeatureNotActivated(ret), "unknown selector must not be masked while inactive");
    }

    /// @notice A malformed view reaches ABI decode rather than the gate.
    /// @dev Bare selector (no args) is too short to decode for every view.
    function test_dispatch_revert_malformedViewReachesDecode(uint8 viewIdx) public {
        vm.skip(!_forkMode());
        _ensureInactive();

        bytes4 selector = _viewSelectors()[viewIdx % 4];
        (bool ok, bytes memory ret) = StdPrecompiles.POLICY_REGISTRY_ADDRESS.staticcall(abi.encodePacked(selector));
        assertFalse(ok, "malformed view call must revert");
        assertFalse(_isFeatureNotActivated(ret), "malformed view must reach decode, not the gate");
    }

    /// @notice Write selectors stay gated by `FeatureNotActivated` while inactive.
    /// @dev Gate fires before arg decode, so a bare (malformed) write selector still hits it.
    function test_dispatch_revert_writeGatedWhileInactive(uint8 writeIdx) public {
        vm.skip(!_forkMode());
        _ensureInactive();

        bytes4 selector = _writeSelectors()[writeIdx % 7];
        (bool ok, bytes memory ret) = StdPrecompiles.POLICY_REGISTRY_ADDRESS.call(abi.encodePacked(selector));
        assertFalse(ok, "write call must revert while inactive");
        assertTrue(_isFeatureNotActivated(ret), "malformed write must stay gated while inactive");
    }
}
