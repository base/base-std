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
///         new higher-numbered bits. Default-token bits live in 0..15;
///         variants (Security 16..23, Stablecoin 24..31) define additional
///         bits in their own ranges to avoid collisions.
///
///         Granular pause control (which operations can be paused while the
///         token is in a partial-pause state) is governed by `PauseVectors`,
///         not by capability bits. A token whose `PAUSABLE` capability is
///         unset cannot be paused at all; a token whose `PAUSABLE` is set
///         can be paused on any combination of vectors. Capability bits
///         govern whether a function exists at all; pause vectors govern
///         which existing functions are temporarily halted.
library Capabilities {
    /*//////////////////////////////////////////////////////////////
                         Default-token bits (0..15)
    //////////////////////////////////////////////////////////////*/

    /// @notice `pause(uint256)` and `unpause()` are callable. When unset,
    ///         the token can never be paused: `pause` reverts with
    ///         `FeatureDisabled`, `paused()` always returns 0.
    uint256 internal constant PAUSABLE = 1 << 0;

    /// @notice `setSupplyCap(uint256)` is callable. When unset, the
    ///         supply cap set at creation is permanent.
    uint256 internal constant CAP_MUTABLE = 1 << 1;

    // Bits 2..15 reserved for future Default-token capabilities.
    //
    // Note that several capability bits from earlier drafts have been
    // removed because the team decided their underlying behavior should
    // simply not exist in the protocol surface, OR because the desired
    // guarantee can be expressed using existing primitives without a
    // dedicated bit:
    //   - MINTABLE: removed. Tokens that want "fixed supply forever"
    //     achieve it by setting `supplyCap == initialSupply` at creation
    //     with `CAP_MUTABLE` unset; `mint` then always reverts with
    //     `SupplyCapExceeded`. Tokens that want "no minting right now
    //     but maybe later" simply leave `MINT_ROLE` ungranted.
    //   - BURNABLE: burn is unconditionally available; tokens that don't
    //     want burns simply never grant BURN_ROLE. Per the PRD, there is
    //     no irreversible-disable opt-out for burn at the protocol level.
    //   - BURN_BLOCKED: force-burn from policy-blocked addresses is not
    //     in the Default surface at all; sanctions seizure is a
    //     periphery / variant concern.
    //   - ADMIN_MUTABLE: role management is always available per the
    //     OZ AccessControl pattern adopted in this draft.
    //   - POLICY_MUTABLE: admin can always swap the transfer policy ID
    //     (the policy itself can also evolve via its own admin in the
    //     registry).
    //   - URI_MUTABLE: contract URI updates are always available to
    //     admin; an issuer that wants a fixed URI simply never updates it.

    /*//////////////////////////////////////////////////////////////
                       Security-variant bits (16..23)
    //////////////////////////////////////////////////////////////*/

    /// @notice On a Security token, `create()` is callable. When unset, the
    ///         compliant issuance path is permanently disabled.
    uint256 internal constant SECURITY_CREATABLE = 1 << 16;

    /// @notice On a Security token, `redeem()` is callable. When unset,
    ///         off-chain redemption via the security-specific path is
    ///         permanently disabled.
    uint256 internal constant SECURITY_REDEEMABLE = 1 << 17;

    /// @notice On a Security token, `updateShareRatio()` is callable. When
    ///         unset, the token-to-share ratio set at creation (typically
    ///         1:1) is permanent.
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
                       Stablecoin-variant bits (24..31)
    //////////////////////////////////////////////////////////////*/

    // The Stablecoin variant currently has no variant-specific
    // capability bits. Bits 24..31 are reserved for future stablecoin
    // additions.
    //
    // Earlier drafts defined STABLECOIN_MINT_RATE_LIMITED (per-minter
    // rate limiting) and STABLECOIN_AUTHORIZATIONS (ERC-3009). Both
    // were removed when the corresponding surface moved out of
    // `IB20Stablecoin` to EVM periphery contracts. See `IB20Stablecoin` for
    // the rationale.

    /*//////////////////////////////////////////////////////////////
                                Presets
    //////////////////////////////////////////////////////////////*/

    /// @notice All currently-defined optional features enabled. Useful as
    ///         the maximum-capability baseline for tokens under active
    ///         governance.
    uint256 internal constant ALL = PAUSABLE | CAP_MUTABLE | SECURITY_CREATABLE | SECURITY_REDEEMABLE
        | SHARE_RATIO_MUTABLE | SECURITY_METADATA_MUTABLE | SECURITY_ADMIN_BATCH;

    /// @notice Zero optional features. The token is a permissioned-free
    ///         ERC-20 with permit and memo support and nothing else: no
    ///         pause, no cap updates. Combined with
    ///         `supplyCap == initialSupply` at creation, this is the
    ///         "fixed supply forever" memecoin shape: future mints
    ///         always revert because the cap can never be raised.
    uint256 internal constant IMMUTABLE_MEMECOIN = 0;

    /// @notice Pausable, permanently-fixed supply. The supply cap (set
    ///         to initial supply at creation) is locked and admin can
    ///         pause and manage roles. No further mints are possible
    ///         because the cap can never be raised. Suitable for tokens
    ///         with a one-time issuance followed by ongoing operational
    ///         governance.
    uint256 internal constant FIXED_SUPPLY = PAUSABLE;

    /// @notice Standard equity-style security token: supports compliant
    ///         issuance via `create`, user redemption via `redeem`,
    ///         share-ratio updates (for splits), all metadata updates, and
    ///         cold-path admin batch operations. Pausable; supply cap
    ///         mutable.
    uint256 internal constant STANDARD_EQUITY = PAUSABLE | CAP_MUTABLE | SECURITY_CREATABLE | SECURITY_REDEEMABLE
        | SHARE_RATIO_MUTABLE | SECURITY_METADATA_MUTABLE | SECURITY_ADMIN_BATCH;

    /// @notice Standard payment-rail stablecoin: pausable, supply cap
    ///         mutable. Per-minter rate limiting and ERC-3009 are not
    ///         on the protocol surface; issuers add them via periphery
    ///         contracts that hold `MINT_ROLE` on the precompile.
    uint256 internal constant STANDARD_STABLECOIN = PAUSABLE | CAP_MUTABLE;
}
