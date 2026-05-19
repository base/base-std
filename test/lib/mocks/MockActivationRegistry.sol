// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IActivationRegistry} from "src/interfaces/IActivationRegistry.sol";

/// @notice Placeholder mock for the `IActivationRegistry` precompile.
///
/// Implements `admin()` returning the same hardcoded address the live
/// precompile uses (per base/base#2733: 0xcb00…0000), so test setUp
/// can resolve `activationAdmin` without reverting. Every other
/// method reverts pending the full mock implementation in a follow-up
/// PR.
contract MockActivationRegistry is IActivationRegistry {
    address internal constant ADMIN = 0xCB00000000000000000000000000000000000000;

    function admin() external pure returns (address) {
        return ADMIN;
    }

    function isActivated(bytes32) external pure returns (bool) {
        revert("MockActivationRegistry: not implemented");
    }

    function activate(bytes32) external pure {
        revert("MockActivationRegistry: not implemented");
    }

    function deactivate(bytes32) external pure {
        revert("MockActivationRegistry: not implemented");
    }
}
