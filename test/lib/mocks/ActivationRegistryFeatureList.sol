// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Canonical feature id constants for the activation registry.
library ActivationRegistryFeatureList {
    /// @dev keccak256("base.b20_asset")
    bytes32 internal constant B20_ASSET = 0xcdcc772fe4cbdb1029f822861176d09e646db96723d4c1e82ddfdeb8163ef54c;

    /// @dev keccak256("base.policy_registry")
    bytes32 internal constant POLICY_REGISTRY = 0xb582ebae03f16fee49a6763f78df482fb11ae73f103ed0d330bbe556aa90a43f;

    /// @dev keccak256("base.b20_stablecoin")
    bytes32 internal constant B20_STABLECOIN = 0xecfa0def2c10020caaf65e6155aa69c84b24892aaef76eeac52e0e2b3a0b8601;
}
