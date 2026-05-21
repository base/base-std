// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IActivationRegistry
/// @notice Singleton precompile that gates Base-native features behind
///         an activation admin. Each feature is identified by an opaque
///         `bytes32` feature id and is either active or inactive;
///         consumers (other precompiles, system configuration, or
///         downstream contracts) consult `isActivated` to gate behavior.
///
///         The activation admin is the only address authorized to call
///         `activate` or `deactivate`; all other callers revert with
///         `Unauthorized`.
///
/// @dev    The precompile enforces two call-context invariants that are
///         surfaced as reverts but cannot originate from normal Solidity
///         consumers:
///         - `DelegateCallNotAllowed`: the precompile MUST be invoked
///           via `CALL` (not `DELEGATECALL` or `CALLCODE`), so the admin
///           identity is bound to `msg.sender` rather than the calling
///           contract's storage context.
///         - `StaticCallNotAllowed`: activation control mutates state and
///           cannot be invoked from a `STATICCALL` frame.
///
///         Feature ids are opaque to the registry: it does not interpret
///         them, and any `bytes32` is a valid id. By convention the
///         producing component picks a stable id derived from a
///         human-readable feature name (the chain-node source uses
///         32-byte digests for this purpose).
interface IActivationRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice `caller` is not the activation admin and is therefore
    ///         not authorized to call `activate` or `deactivate`.
    error Unauthorized(address caller);

    /// @notice `activate` was called on a feature that is already
    ///         activated.
    error AlreadyActivated(bytes32 feature);

    /// @notice `deactivate` was called on a feature that is already
    ///         deactivated.
    error AlreadyDeactivated(bytes32 feature);

    /// @notice `feature` is not activated. Returned by `deactivate` and
    ///         by precompiles that consult the registry as a hard gate
    ///         (the chain node uses an `assertActivated`-style flow for
    ///         this); not raised by `isActivated`, which returns `false`
    ///         instead.
    error FeatureNotActivated(bytes32 feature);

    /// @notice The precompile was invoked via `DELEGATECALL` or
    ///         `CALLCODE`. All entry points require a direct `CALL`.
    error DelegateCallNotAllowed();

    /// @notice A state-mutating entry point (`activate` or `deactivate`)
    ///         was invoked from a `STATICCALL` frame.
    error StaticCallNotAllowed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `feature` transitions from inactive to
    ///         activated. `caller` is the activation admin.
    event FeatureActivated(bytes32 indexed feature, address indexed caller);

    /// @notice Emitted when `feature` transitions from activated to
    ///         inactive. `caller` is the activation admin.
    event FeatureDeactivated(bytes32 indexed feature, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `feature` is currently activated. Returns
    ///         `false` for any feature id that has never been activated
    ///         or has since been deactivated.
    function isActivated(bytes32 feature) external view returns (bool);

    /// @notice The address authorized to call `activate` and `deactivate`.
    function admin() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Activates `feature`. Caller MUST equal `admin()` (else
    ///         `Unauthorized`). Reverts with `AlreadyActivated` if the
    ///         feature is already activated; reverts with
    ///         `StaticCallNotAllowed` if invoked under `STATICCALL`.
    ///         Emits `FeatureActivated` on success.
    function activate(bytes32 feature) external;

    /// @notice Deactivates `feature`. Caller MUST equal `admin()` (else
    ///         `Unauthorized`). Reverts with `AlreadyDeactivated` if
    ///         the feature is already deactivated; reverts with
    ///         `StaticCallNotAllowed` if invoked under `STATICCALL`.
    ///         Emits `FeatureDeactivated` on success.
    function deactivate(bytes32 feature) external;
}
