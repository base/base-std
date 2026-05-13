// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title Capabilities
/// @notice Bit flags identifying optional features on a Base-native token (B-20).
///         A token's `capabilities()` value is set at creation by the factory
///         and is permanent. Functions whose capability bit is unset revert
///         with `FeatureDisabled`, regardless of role state. Functions whose
///         bit IS set are subject to the normal role-based access control on
///         top.
/// @dev    Bits are append-only across protocol versions. Once a bit's meaning
///         is published, it cannot be reused or repurposed; new features get
///         new higher-numbered bits. Default-token bits start at `1 << 0`;
///         variants (Stablecoin, Security, ...) may define additional bits in
///         their own ranges to avoid collisions.
library Capabilities {
    /*//////////////////////////////////////////////////////////////
                         Default token bits (0..15)
    //////////////////////////////////////////////////////////////*/

    /// @notice `pause()` and `unpause()` are callable.
    uint256 internal constant PAUSABLE = 1 << 0;

    /// @notice `mint()` and `mintWithMemo()` are callable.
    uint256 internal constant MINTABLE = 1 << 1;

    /// @notice `burn()` and `burnWithMemo()` are callable.
    uint256 internal constant BURNABLE = 1 << 2;

    /// @notice `burnBlocked()` is callable. Gated separately from `BURNABLE`
    ///         so issuers can permit normal burns while disabling
    ///         compliance-style force-burns, or vice versa.
    uint256 internal constant BURN_BLOCKED = 1 << 3;

    /// @notice `grantRole`, `revokeRole`, and `setRoleAdmin` are callable.
    ///         When unset, the role configuration written by the factory at
    ///         creation is permanent. Holders may still `renounceRole`
    ///         themselves; renunciation is always allowed.
    uint256 internal constant ADMIN_MUTABLE = 1 << 4;

    /// @notice `changeTransferPolicyId()` is callable. When unset, the policy
    ///         ID set at creation is permanent. Note: the membership of the
    ///         referenced policy can still change because that is controlled
    ///         by the policy admin in the registry, not by the token.
    uint256 internal constant POLICY_MUTABLE = 1 << 5;

    /// @notice `setSupplyCap()` is callable. When unset, the supply cap set
    ///         at creation is permanent.
    uint256 internal constant CAP_MUTABLE = 1 << 6;

    /// @notice `setContractURI()` is callable. When unset, the contract URI
    ///         set at creation is permanent.
    uint256 internal constant URI_MUTABLE = 1 << 7;

    /*//////////////////////////////////////////////////////////////
                                Presets
    //////////////////////////////////////////////////////////////*/

    /// @notice Every Default-token feature enabled. The standard configuration
    ///         for tokens that expect to operate under active governance:
    ///         stablecoins, wrapped assets, institutional-issued tokens.
    uint256 internal constant ALL = type(uint256).max;

    /// @notice Zero optional features. The token is a permissioned-free
    ///         ERC-20 with permit and memo support and nothing else: no
    ///         admin, no pause, no further mints or burns after the initial
    ///         supply, no policy changes, no URI changes. Supply is whatever
    ///         was minted at creation, locked forever. Suitable for
    ///         permissionless meme coins and similar credibly-neutral tokens.
    uint256 internal constant IMMUTABLE_MEMECOIN = 0;

    /// @notice Admin can pause, change the transfer policy, manage roles, and
    ///         update the contract URI, but supply is permanently fixed (no
    ///         further mints or burns of any kind). Suitable for tokens with
    ///         a one-time issuance event followed by ongoing operational
    ///         governance.
    uint256 internal constant FIXED_SUPPLY = PAUSABLE | ADMIN_MUTABLE | POLICY_MUTABLE | URI_MUTABLE;
}
