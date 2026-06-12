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
        return livePrecompiles;
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

    /// @dev Well-formed (ABI-decodable) calldata for write selector `idx`, ordered to match
    ///      `_writeSelectors()`. The activation gate sits behind selector routing and ABI decode and
    ///      fires before any argument validation, so the concrete values are immaterial — what matters
    ///      is that the payload decodes cleanly and therefore reaches the gate.
    function _writeCalldata(uint8 idx) internal pure returns (bytes memory) {
        address[] memory accounts = new address[](1);
        accounts[0] = address(0xBEEF);
        if (idx == 0) {
            return abi.encodeCall(IPolicyRegistry.createPolicy, (address(0xBEEF), IPolicyRegistry.PolicyType.ALLOWLIST));
        }
        if (idx == 1) {
            return abi.encodeCall(
                IPolicyRegistry.createPolicyWithAccounts,
                (address(0xBEEF), IPolicyRegistry.PolicyType.ALLOWLIST, accounts)
            );
        }
        if (idx == 2) return abi.encodeCall(IPolicyRegistry.stageUpdateAdmin, (uint64(1), address(0xBEEF)));
        if (idx == 3) return abi.encodeCall(IPolicyRegistry.finalizeUpdateAdmin, (uint64(1)));
        if (idx == 4) return abi.encodeCall(IPolicyRegistry.renounceAdmin, (uint64(1)));
        if (idx == 5) return abi.encodeCall(IPolicyRegistry.updateAllowlist, (uint64(1), true, accounts));
        return abi.encodeCall(IPolicyRegistry.updateBlocklist, (uint64(1), true, accounts));
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

    /// @notice Well-formed write calls stay gated by `FeatureNotActivated` while inactive.
    /// @dev The gate sits behind selector routing and ABI decode, so the payload must be well-formed
    ///      to reach it: a bare selector would revert in decode instead, which is exactly what the
    ///      dispatch-ordering fix makes observable. Concrete arg values are immaterial because the gate
    ///      fires before any argument validation.
    function test_dispatch_revert_writeGatedWhileInactive(uint8 writeIdx) public {
        vm.skip(!_forkMode());
        _ensureInactive();

        bytes memory payload = _writeCalldata(writeIdx % 7);
        (bool ok, bytes memory ret) = StdPrecompiles.POLICY_REGISTRY_ADDRESS.call(payload);
        assertFalse(ok, "write call must revert while inactive");
        assertTrue(_isFeatureNotActivated(ret), "write must stay gated while inactive");
    }
}
