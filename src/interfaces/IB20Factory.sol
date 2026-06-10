// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IB20Factory
///
/// @notice Singleton factory precompile for creating B-20 tokens of any variant. A single
///         entry point `createB20` dispatches on a `B20Variant` discriminator; variant-specific
///         arguments are ABI-encoded into `params` with a leading `version` byte.
interface IB20Factory {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Variant of a B-20 token. Encoded in address byte `[10]`.
    ///
    /// @param ASSET      Asset variant (configurable `decimals`, multiplier, announcements, batched issuance / clawback).
    /// @param STABLECOIN Stablecoin variant (fixed `6` decimals, immutable `currency`).
    enum B20Variant {
        ASSET,
        STABLECOIN
    }

    /// @notice Creation parameters for a Stablecoin-variant B-20 token. ABI-encoded into `params`.
    struct B20StablecoinCreateParams {
        /// @dev Encoding version. Currently `1`.
        uint8 version;
        /// @dev ERC-20 token name.
        string name;
        /// @dev ERC-20 token symbol.
        string symbol;
        /// @dev Initial holder of `DEFAULT_ADMIN_ROLE`, or `address(0)` to deploy admin-less.
        address initialAdmin;
        /// @dev Immutable self-declared currency code; uppercase ASCII `A`-`Z` only.
        string currency;
    }

    /// @notice Creation parameters for an Asset-variant B-20 token. ABI-encoded into `params`.
    struct B20AssetCreateParams {
        /// @dev Encoding version. Currently `1`.
        uint8 version;
        /// @dev ERC-20 token name.
        string name;
        /// @dev ERC-20 token symbol.
        string symbol;
        /// @dev Initial holder of `DEFAULT_ADMIN_ROLE`, or `address(0)` to deploy admin-less.
        address initialAdmin;
        /// @dev ERC-20 `decimals` value. Immutable post-creation. Must be in the inclusive
        ///      range `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]`
        ///      (`[6, 18]`); out-of-range values revert with `InvalidDecimals`.
        uint8 decimals;
    }

    /// @notice Event payload carried in the `variantEventParams` field of `B20Created` for
    ///         STABLECOIN-variant tokens. ABI-encoded and prefixed with a version byte.
    struct B20StablecoinEventParams {
        /// @dev Event-encoding version. Currently `1`. Independent of `B20StablecoinCreateParams.version`.
        uint8 version;
        /// @dev Stablecoin currency code, identical to the value passed in
        ///      `B20StablecoinCreateParams.currency`.
        string currency;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH was attached to a call targeting a nonpayable factory selector.
    error NonPayable();

    /// @notice A token already exists at the deterministic address derived from
    ///         `(variant, msg.sender, salt)`. Caller must use a different salt.
    error TokenAlreadyExists(address token);

    /// @notice `variant` is not a recognized `B20Variant`.
    error InvalidVariant();

    /// @notice The leading `version` byte in `params` does not match any known encoding for the requested variant.
    error UnsupportedVersion(uint8 version, B20Variant variant);

    /// @notice A required string argument was the empty string.
    ///
    /// @param field Name of the missing field (e.g. `"currency"`).
    error MissingRequiredField(string field);

    /// @notice The stablecoin `currency` was non-empty but contained a non-`A`-`Z` byte.
    error InvalidCurrency(string code);

    /// @notice The asset `decimals` was outside the allowed inclusive range
    ///         `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]`.
    ///
    /// @param decimals Offending decimals value.
    error InvalidDecimals(uint8 decimals);

    /// @notice One of the `initCalls` reverted. The factory bubbles the underlying revert reason
    ///         where the call returns one; this error wraps empty reverts.
    error InitCallFailed(uint256 index);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once per `createB20` invocation, after the token's identity is sealed
    ///         and before any `initCalls` are dispatched.
    ///
    /// @dev `variantEventParams` carries variant-specific immutable identity data, ABI-encoded
    ///      and prefixed with a version byte. Empty for ASSET; for STABLECOIN,
    ///      `abi.encode(B20StablecoinEventParams)` with `currency`.
    /// @dev `decimals` mirrors the value chosen at creation: configurable in
    ///      `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]` for ASSET
    ///      (from `B20AssetCreateParams.decimals`); hardcoded to `6` for STABLECOIN.
    event B20Created(
        address indexed token,
        B20Variant indexed variant,
        string name,
        string symbol,
        uint8 decimals,
        bytes variantEventParams
    );

    /*//////////////////////////////////////////////////////////////
                                 CREATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a B-20 token of the given `variant` at the deterministic address derived
    ///         from `(variant, msg.sender, salt)`, then dispatches each entry in `initCalls` on
    ///         the new token. Emits `B20Created`.
    ///
    /// @dev Reverts with `NonPayable` when ETH is attached to the call.
    /// @dev Reverts with IActivationRegistry.FeatureNotActivated when the variant feature is not activated.
    /// @dev Reverts with `InvalidVariant` when `variant` is outside the `B20Variant` range.
    /// @dev Reverts with `UnsupportedVersion` when the leading `version` byte in `params` is unrecognized for `variant`.
    /// @dev Reverts with `MissingRequiredField` when a required string field is empty (e.g. stablecoin `currency`).
    /// @dev Reverts with `InvalidCurrency` when a stablecoin `currency` is non-empty but contains a non-`A`-`Z` byte.
    /// @dev Reverts with `InvalidDecimals` when an asset `decimals` is outside `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]`.
    /// @dev Reverts with `TokenAlreadyExists` when a token already exists at the derived address.
    /// @dev Reverts with `InitCallFailed` (or the bubbled inner reason) when any entry in `initCalls` reverts.
    /// @dev Each `initCall` executes on the new token within the creation (bootstrap) window, during which
    ///      factory-originated calls bypass the token's role gates and its transfer-side policy gates
    ///      (`TRANSFER_SENDER_POLICY`, `TRANSFER_RECEIVER_POLICY`, `TRANSFER_EXECUTOR_POLICY`) — so admin-gated
    ///      setup (e.g. `grantRole`, `updatePolicy`, `updateSupplyCap`) and bootstrap transfers succeed without
    ///      the factory holding any role. The bypass is deliberately NOT total:
    ///      - `MINT_RECEIVER_POLICY` is ALWAYS enforced, including for factory-originated mints, so new supply is
    ///        never issued to a policy-denied recipient even at creation. An `initCalls` bundle that sets a
    ///        restrictive `MINT_RECEIVER_POLICY` and then mints to a non-authorized account reverts
    ///        `PolicyForbids(MINT_RECEIVER_POLICY, ...)` (bubbled out of `createB20`).
    ///      - Pause is never bypassed. It defaults to nothing-paused at creation, so a start-paused
    ///        configuration must sequence its `pause(...)` call last among the `initCalls`.
    ///      - Token invariants (supply-cap math, balance accounting) are never bypassed.
    ///      The window closes when `createB20` returns; the factory retains no persisted access.
    ///
    /// @param variant   Which variant struct `params` decodes as.
    /// @param salt      Caller-chosen salt for deterministic address derivation.
    /// @param params    ABI-encoded variant-specific creation struct, leading with the version byte.
    /// @param initCalls Bootstrap calls invoked on the new token after identity is sealed.
    ///
    /// @return token The address of the newly created token.
    function createB20(B20Variant variant, bytes32 salt, bytes calldata params, bytes[] calldata initCalls)
        external
        payable
        returns (address token);

    /*//////////////////////////////////////////////////////////////
                            ADDRESS QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deterministic address `createB20` would assign for `(variant, sender, salt)`. Never reverts.
    ///
    /// @param variant Variant of the token whose address is being predicted.
    /// @param sender  Account that would call `createB20`.
    /// @param salt    Caller-chosen salt.
    ///
    /// @return The deterministic token address.
    function getB20Address(B20Variant variant, address sender, bytes32 salt) external view returns (address);

    /// @notice Returns whether `token` was created by this factory, recovered from the address prefix. Never reverts.
    ///
    /// @param token Address to check.
    ///
    /// @return Whether `token` matches the B-20 address prefix.
    function isB20(address token) external view returns (bool);

    /// @notice Returns whether `createB20` has run to completion at `token`. Flips exactly once,
    ///         the moment the creating `createB20` call returns. Never reverts.
    ///
    /// @param token Address to check.
    ///
    /// @return Whether `token` is an initialized B-20.
    function isB20Initialized(address token) external view returns (bool);
}
