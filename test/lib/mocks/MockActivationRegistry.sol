// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "base-std/interfaces/IActivationRegistry.sol";

import {MockActivationRegistryStorage} from "base-std-test/lib/mocks/MockActivationRegistryStorage.sol";

/// @title MockActivationRegistry
/// @notice Reference implementation of the `IActivationRegistry` precompile.
///         Etched at the canonical activation-registry address via `vm.etch`
///         from `BaseTest.setUp`.
///
/// @dev    Solidity-as-if-Rust: spec-correspondence with the production
///         Rust precompile, not gas-optimal Solidity. All mutable state
///         lives in `MockActivationRegistryStorage.layout()` at a single
///         ERC-7201-namespaced root; see that library for the layout.
///
///         **Admin model.** `admin()` returns a hardcoded constant
///         (`0xCB00…0000`) — the production
///         precompile and this mock both expose the same fixed admin
///         identity. There is no storage-backed admin slot and no
///         admin-rotation surface; replacing the admin requires a
///         chain-node change.
///
///         **Call-context invariants not enforced here.** The
///         IActivationRegistry NatSpec specifies two invariants
///         (`DelegateCallNotAllowed`, `StaticCallNotAllowed`) that
///         "cannot originate from normal Solidity consumers". The
///         precompile enforces them in the Rust call-frame machinery;
///         the etched Solidity mock cannot meaningfully reproduce them
///         (it has no way to observe DELEGATECALL vs CALL on its own
///         entry, and STATICCALL on a state-mutating function reverts
///         at the EVM level before any user code runs). The errors are
///         defined on the interface so consumer ABIs can decode them
///         when produced by the live precompile.
contract MockActivationRegistry is IActivationRegistry {
    // ============================================================
    //                         CONSTANTS
    // ============================================================

    /// @notice The activation admin address. Hardcoded to the same value the
    ///         live Rust precompile returns (`0xCB00…0000`),
    ///         so tests and consumers can pin the admin identity without
    ///         depending on per-environment configuration.
    address internal constant ADMIN = 0xCB00000000000000000000000000000000000000;

    // ============================================================
    //                       ADMIN QUERIES
    // ============================================================

    /// @inheritdoc IActivationRegistry
    function admin() external pure returns (address) {
        return ADMIN;
    }

    // ============================================================
    //                     ACTIVATION QUERIES
    // ============================================================

    /// @inheritdoc IActivationRegistry
    function isActivated(bytes32 feature) external view returns (bool) {
        return MockActivationRegistryStorage.layout().features[feature];
    }

    /// @inheritdoc IActivationRegistry
    function checkActivated(bytes32 feature) external view {
        if (!MockActivationRegistryStorage.layout().features[feature]) revert FeatureNotActivated(feature);
    }

    // ============================================================
    //                     ACTIVATION CONTROL
    // ============================================================

    /// @inheritdoc IActivationRegistry
    function activate(bytes32 feature) external {
        if (msg.sender != ADMIN) revert Unauthorized(msg.sender);
        MockActivationRegistryStorage.Layout storage $ = MockActivationRegistryStorage.layout();
        if ($.features[feature]) revert AlreadyActivated(feature);
        $.features[feature] = true;
        emit FeatureActivated(feature, msg.sender);
    }

    /// @inheritdoc IActivationRegistry
    function deactivate(bytes32 feature) external {
        if (msg.sender != ADMIN) revert Unauthorized(msg.sender);
        MockActivationRegistryStorage.Layout storage $ = MockActivationRegistryStorage.layout();
        // FeatureNotActivated covers both "never activated" and "previously
        // deactivated"; the boolean storage cannot distinguish the two and
        // the interface NatSpec authorizes this single error for the
        // "feature is not currently activated" case on `deactivate`.
        if (!$.features[feature]) revert FeatureNotActivated(feature);
        $.features[feature] = false;
        emit FeatureDeactivated(feature, msg.sender);
    }
}
