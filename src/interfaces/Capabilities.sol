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
                       Security-token bits (16..23)
    //////////////////////////////////////////////////////////////*/

    /// @notice On a Security token, `create()` is callable. When unset, the
    ///         compliant issuance path is permanently disabled (the token's
    ///         supply is effectively frozen except for `adminMint` /
    ///         `adminBurn`, if those are also enabled).
    uint256 internal constant SECURITY_CREATABLE = 1 << 16;

    /// @notice On a Security token, `redeem()` is callable. When unset,
    ///         off-chain redemption via the security-specific path is
    ///         permanently disabled (holders can still self-burn via the
    ///         inherited `burn` if `BURNABLE` is set).
    uint256 internal constant SECURITY_REDEEMABLE = 1 << 17;

    /// @notice On a Security token, `updateShareRatio()` is callable. When
    ///         unset, the token-to-share ratio set at creation (typically
    ///         1:1) is permanent. Useful for securities that will never
    ///         split (most ETFs, single-class commodities).
    uint256 internal constant SHARE_RATIO_MUTABLE = 1 << 18;

    /// @notice On a Security token, `updateName` / `updateSymbol` /
    ///         `updateSecurityIdentifier` are callable. When unset, the
    ///         identifying metadata set at creation is permanent.
    uint256 internal constant SECURITY_METADATA_MUTABLE = 1 << 19;

    /// @notice On a Security token, `adminMint()` and `adminBurn()` are
    ///         callable. When unset, the cold-path batch operations are
    ///         permanently disabled.
    uint256 internal constant SECURITY_ADMIN_BATCH = 1 << 20;

    /*//////////////////////////////////////////////////////////////
                       Stablecoin-token bits (24..31)
    //////////////////////////////////////////////////////////////*/

    /// @notice On a Stablecoin token, per-minter rate limiting is enforced
    ///         on `mint()` / `mintWithMemo()`. `configureMinter`,
    ///         `grantMinterRoleWithLimit`, `currentMintLimit`, and
    ///         `mintRateLimitConfig` are callable. When unset, the
    ///         stablecoin still has `MINT_ROLE` gating but no rate limiting:
    ///         a holder of MINT_ROLE may mint freely up to the inherited
    ///         `supplyCap`.
    uint256 internal constant STABLECOIN_MINT_RATE_LIMITED = 1 << 24;

    /// @notice On a Stablecoin token, ERC-3009 `transferWithAuthorization`,
    ///         `receiveWithAuthorization`, and `cancelAuthorization` are
    ///         callable. When unset, the gasless-transfer surface is
    ///         permanently disabled (holders fall back to ERC-20 + EIP-2612
    ///         permit).
    uint256 internal constant STABLECOIN_AUTHORIZATIONS = 1 << 25;

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

    /// @notice Standard equity-style security token: supports compliant
    ///         issuance via `create`, user redemption via `redeem`,
    ///         share-ratio updates (for splits), all metadata updates, and
    ///         cold-path admin batch operations. Inherited mint/burn paths
    ///         are disabled in favor of the security-specific functions;
    ///         BURN_BLOCKED stays on for sanctions enforcement.
    uint256 internal constant STANDARD_EQUITY = PAUSABLE | BURN_BLOCKED | ADMIN_MUTABLE | POLICY_MUTABLE | CAP_MUTABLE
        | URI_MUTABLE | SECURITY_CREATABLE | SECURITY_REDEEMABLE | SHARE_RATIO_MUTABLE | SECURITY_METADATA_MUTABLE
        | SECURITY_ADMIN_BATCH;

    /// @notice Standard payment-rail stablecoin: supports rate-limited mint
    ///         (per-minter quotas), burn, ERC-3009 gasless transfers, pause,
    ///         and full admin / policy / URI mutability. Does NOT include
    ///         BURN_BLOCKED (matches the "freeze, never seize" philosophy
    ///         of CDP Custom Stablecoin and similar). Issuers who want
    ///         force-burn for sanctions enforcement can OR `BURN_BLOCKED`
    ///         in at creation.
    uint256 internal constant STANDARD_STABLECOIN = PAUSABLE | MINTABLE | BURNABLE | ADMIN_MUTABLE | POLICY_MUTABLE
        | CAP_MUTABLE | URI_MUTABLE | STABLECOIN_MINT_RATE_LIMITED | STABLECOIN_AUTHORIZATIONS;
}
