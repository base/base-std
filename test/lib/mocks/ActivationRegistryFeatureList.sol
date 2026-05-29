// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Canonical feature id constants for the activation registry.
library ActivationRegistryFeatureList {
    /// @dev keccak256("base.b20_security")
    bytes32 internal constant B20_ASSET = 0x83d32fab502ae0e8bc4352a117767262cb5e47cc8d67a744008ed4ff03fcf5e6;

    /// @dev keccak256("base.b20_token")
    bytes32 internal constant B20_TOKEN = 0x47a1afe8d3d691b87e090ee972d223a11f4da971ff5416c04985bb2393aca752;

    /// @dev keccak256("base.b20_factory")
    bytes32 internal constant B20_FACTORY = 0x78751e29c8bcc0d609ab18e9fbc4158e73f7db25ae2ee095dad42e2578b1e800;

    /// @dev keccak256("base.policy_registry")
    bytes32 internal constant POLICY_REGISTRY = 0xb582ebae03f16fee49a6763f78df482fb11ae73f103ed0d330bbe556aa90a43f;

    /// @dev keccak256("base.b20_stablecoin")
    bytes32 internal constant B20_STABLECOIN = 0xecfa0def2c10020caaf65e6155aa69c84b24892aaef76eeac52e0e2b3a0b8601;
}
