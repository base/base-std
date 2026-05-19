// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IActivationRegistry
/// @notice Singleton precompile that gates Base-native features behind an
///         activation admin. Each feature is identified by an opaque `bytes32`
///         id and is either enabled or disabled; all features default to
///         disabled. The admin can call `enable` or `disable`; any other
///         caller reverts with `Unauthorized`. No-op transitions (enabling an
///         already-enabled feature or disabling an already-disabled feature)
///         also revert.
///
/// @dev    The precompile enforces two call-context invariants surfaced as ABI
///         reverts:
///         - `DelegateCallNotAllowed`: entry points require a direct `CALL`.
///           `DELEGATECALL` / `CALLCODE` are rejected so the caller identity is
///           bound to `msg.sender`, not the calling contract's storage context.
///         - `StaticCallNotAllowed`: `enable` and `disable` mutate state and
///           cannot be invoked from a `STATICCALL` frame.
///
///         Feature ids are opaque to the registry: any `bytes32` is a valid id.
///         By convention the producing component picks a stable id derived from
///         a human-readable feature name (the chain-node source uses 32-byte
///         digests for this purpose).
///
///         `FeatureNotEnabled` is raised by consumers that call an
///         `assertEnabled`-style gate on a disabled feature, not by `isEnabled`
///         itself (which returns `false` instead).
interface IActivationRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice `caller` is not the activation admin and is therefore not
    ///         authorized to call `enable` or `disable`.
    error Unauthorized(address caller);

    /// @notice `enable` was called on a feature that is already enabled.
    error AlreadyEnabled(bytes32 feature);

    /// @notice `disable` was called on a feature that is already disabled.
    error AlreadyDisabled(bytes32 feature);

    /// @notice `feature` is not enabled. Raised by consumers that use the
    ///         registry as a hard gate (e.g. an `assertEnabled` pattern);
    ///         not raised by `isEnabled`, which returns `false` instead.
    error FeatureNotEnabled(bytes32 feature);

    /// @notice The precompile was invoked via `DELEGATECALL` or `CALLCODE`.
    ///         All entry points require a direct `CALL`.
    error DelegateCallNotAllowed();

    /// @notice A state-mutating entry point (`enable` or `disable`) was
    ///         invoked from a `STATICCALL` frame.
    error StaticCallNotAllowed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `feature` transitions from disabled to enabled.
    ///         `caller` is the activation admin.
    event FeatureEnabled(bytes32 indexed feature, address indexed caller);

    /// @notice Emitted when `feature` transitions from enabled to disabled.
    ///         `caller` is the activation admin.
    event FeatureDisabled(bytes32 indexed feature, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `feature` is currently enabled. Returns `false` for
    ///         any feature id that has never been enabled (the default state).
    function isEnabled(bytes32 feature) external view returns (bool);

    /// @notice The address authorized to call `enable` and `disable`.
    function activationAdmin() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables `feature`. Caller MUST equal `activationAdmin()` (else
    ///         `Unauthorized`). Reverts with `AlreadyEnabled` if the feature
    ///         is already enabled; reverts with `StaticCallNotAllowed` if
    ///         invoked under `STATICCALL`. Emits `FeatureEnabled` on success.
    function enable(bytes32 feature) external;

    /// @notice Disables `feature`. Caller MUST equal `activationAdmin()` (else
    ///         `Unauthorized`). Reverts with `AlreadyDisabled` if the feature
    ///         is already disabled; reverts with `StaticCallNotAllowed` if
    ///         invoked under `STATICCALL`. Emits `FeatureDisabled` on success.
    function disable(bytes32 feature) external;
}
