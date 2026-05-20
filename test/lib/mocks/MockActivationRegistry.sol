// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "src/interfaces/IActivationRegistry.sol";

/// @notice Placeholder mock for the `IActivationRegistry` precompile.
///
/// Implements `admin()` returning the same hardcoded address the live
/// precompile uses (per base/base#2733: 0xcb00…0000), so test setUp
/// can resolve `activationAdmin` without reverting. `isActivated`
/// returns `false` for every feature id, per the IActivationRegistry
/// NatSpec (L45-47) which carves it out from `FeatureNotActivated`:
/// "not raised by `isActivated`, which returns `false` instead." This
/// matches the production Rust precompile, where unactivated features
/// are observably false rather than triggering an error path.
/// `activate` and `deactivate` revert pending the full state-bearing
/// mock implementation in a follow-up PR.
contract MockActivationRegistry is IActivationRegistry {
    address internal constant ADMIN = 0xCB00000000000000000000000000000000000000;

    function admin() external pure returns (address) {
        return ADMIN;
    }

    function isActivated(bytes32) external pure returns (bool) {
        return false;
    }

    function activate(bytes32) external pure {
        revert("MockActivationRegistry: not implemented");
    }

    function deactivate(bytes32) external pure {
        revert("MockActivationRegistry: not implemented");
    }
}
