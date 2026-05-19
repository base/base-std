// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IActivationRegistry
/// @notice Singleton precompile that gates Base-native features behind
///         an activation admin. Each feature is identified by an opaque
///         `bytes32` feature id and is either enabled or disabled;
///         disabled features cannot be activated by anyone other than
///         the activation admin, and once enabled they remain enabled.
///
///         Consumers (typically other Base precompiles or the system
///         configuration) consult `isEnabled` to gate behavior. The
///         activation admin is the only address authorized to call
///         `enable`; all other callers revert with `Unauthorized`.
///
/// @dev    The precompile enforces two call-context invariants that are
///         surfaced as reverts but cannot originate from normal Solidity
///         consumers:
///         - `DelegateCallNotAllowed`: the precompile MUST be invoked
///           via `CALL` (not `DELEGATECALL` or `CALLCODE`), so the admin
///           identity is bound to `msg.sender` rather than the calling
///           contract's storage context.
///         - `StaticCallNotAllowed`: `enable` mutates state and cannot
///           be invoked from a `STATICCALL` frame.
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
    ///         not authorized to call `enable`.
    error Unauthorized(address caller);

    /// @notice `feature` is already enabled. `enable` is idempotent in
    ///         intent but reverts to signal that the caller's expected
    ///         state transition (disabled -> enabled) did not occur.
    error AlreadyEnabled(bytes32 feature);

    /// @notice `feature` is not enabled. Returned by precompiles that
    ///         consult the registry as a hard gate (see `assertEnabled`-
    ///         style flows in the chain node); not raised by `isEnabled`,
    ///         which returns `false` instead.
    error FeatureNotEnabled(bytes32 feature);

    /// @notice The precompile was invoked via `DELEGATECALL` or
    ///         `CALLCODE`. All entry points require a direct `CALL`.
    error DelegateCallNotAllowed();

    /// @notice A state-mutating entry point (`enable`) was invoked from
    ///         a `STATICCALL` frame.
    error StaticCallNotAllowed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `feature` transitions from disabled to
    ///         enabled. `caller` is the activation admin (the only
    ///         address authorized to flip the bit).
    event FeatureEnabled(bytes32 indexed feature, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `feature` is currently enabled. Returns `false`
    ///         for any feature id that has never been enabled (the
    ///         default state).
    function isEnabled(bytes32 feature) external view returns (bool);

    /// @notice The address authorized to call `enable`.
    function activationAdmin() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables `feature`. Caller MUST equal `activationAdmin()`
    ///         (else `Unauthorized`). Reverts with `AlreadyEnabled` if
    ///         the feature is already enabled; reverts with
    ///         `StaticCallNotAllowed` if invoked under `STATICCALL`.
    ///         Emits `FeatureEnabled` on success. Once enabled, a
    ///         feature cannot be disabled.
    function enable(bytes32 feature) external;
}
