// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IActivationRegistry
/// @notice Singleton precompile for managing runtime feature flags on Base.
///         The registry allows a designated activation admin to irreversibly
///         enable named features (identified by `bytes32` IDs) on the chain.
///         Features default to disabled and can only be enabled, never disabled,
///         providing one-way latch semantics intentionally chosen for safety:
///         once a feature is live, downstream contracts and state may depend on
///         it being available.
///
///         Example use cases include gating tokenized-equity creation rights
///         behind a `SECURITIES_TOKEN_CREATION` flag, or enabling any other
///         Base-native protocol primitive at the appropriate time after a
///         hardfork.
///
/// @dev    Available from the Beryl hardfork. Calling on earlier forks results
///         in the call reverting as there is no code at the precompile address.
///
///         The precompile enforces that:
///         - Only the configured `activationAdmin` may enable features.
///         - Features cannot be enabled via `delegatecall` or `callcode`.
///         - `enable` cannot be called in a static context.
///
///         Other precompiles and contracts may gate their own logic by calling
///         `isEnabled(featureId)` at the start of any feature-gated operation.
///
///         Precompile address: `0x84530000000000000000000000000000000000ff`
interface IActivationRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the activation admin.
    /// @param caller The address that attempted the call.
    error Unauthorized(address caller);

    /// @notice Feature is already enabled; it cannot be enabled again.
    /// @param feature The feature ID that is already on.
    error AlreadyEnabled(bytes32 feature);

    /// @notice Feature is not yet enabled; a gated operation was attempted.
    /// @param feature The feature ID that is still off.
    error FeatureNotEnabled(bytes32 feature);

    /// @notice The precompile was invoked via `delegatecall` or `callcode`.
    error DelegateCallNotAllowed();

    /// @notice A state-mutating call was attempted in a static context.
    error StaticCallNotAllowed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a feature is enabled for the first time.
    /// @param feature The feature ID that was enabled.
    /// @param caller  The activation admin address that enabled it.
    event FeatureEnabled(bytes32 indexed feature, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                           ACTIVATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns true if `feature` is currently enabled.
    /// @param feature The feature ID to query.
    /// @return enabled Whether the feature is enabled.
    function isEnabled(bytes32 feature) external view returns (bool enabled);

    /*//////////////////////////////////////////////////////////////
                          ACTIVATION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables `feature`. One-way: once enabled, a feature cannot
    ///         be disabled.
    /// @dev    Reverts with `Unauthorized` if `msg.sender` is not the
    ///         activation admin. Reverts with `AlreadyEnabled` if the
    ///         feature is already on. Reverts with `StaticCallNotAllowed`
    ///         in a static context, and with `DelegateCallNotAllowed` if
    ///         invoked via `delegatecall` or `callcode`.
    ///
    ///         Emits `FeatureEnabled` on success.
    /// @param feature The feature ID to enable.
    function enable(bytes32 feature) external;

    /*//////////////////////////////////////////////////////////////
                          ADMIN QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the activation admin, the only account
    ///         permitted to call `enable`.
    /// @return admin The activation admin address.
    function activationAdmin() external view returns (address admin);
}