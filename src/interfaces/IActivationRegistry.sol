// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IActivationRegistry
/// @notice Singleton precompile that gates Base-native features behind an activation admin. Each feature
///         is identified by an opaque `bytes32` id and is either active or inactive.
interface IActivationRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the activation admin.
    error Unauthorized(address caller);

    /// @notice Feature is already activated.
    error AlreadyActivated(bytes32 feature);

    /// @notice Feature is not activated.
    error FeatureNotActivated(bytes32 feature);

    /// @notice The precompile was invoked via `DELEGATECALL` or `CALLCODE`.
    error DelegateCallNotAllowed();

    /// @notice A state-mutating entry point was invoked from a `STATICCALL` frame.
    error StaticCallNotAllowed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `feature` is activated.
    event FeatureActivated(bytes32 indexed feature, address indexed caller);

    /// @notice Emitted when `feature` is deactivated.
    event FeatureDeactivated(bytes32 indexed feature, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `feature` is currently activated. Never reverts.
    ///
    /// @param feature Feature to query.
    ///
    /// @return Whether `feature` is activated.
    function isActivated(bytes32 feature) external view returns (bool);

    /// @notice Reverts with `FeatureNotActivated(feature)` if `feature` is not currently activated.
    ///         A pure assertion entry point so callers don't have to redefine the error.
    ///
    /// @dev Reverts with `FeatureNotActivated` when `feature` is not activated.
    ///
    /// @param feature Feature to assert is active.
    function checkActivated(bytes32 feature) external view;

    /// @notice The address authorized to call `activate` and `deactivate`.
    /// @return Current activation admin.
    function admin() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            ACTIVATION CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Activates `feature`. Emits `FeatureActivated`.
    ///
    /// @dev Reverts with `DelegateCallNotAllowed` when invoked via `DELEGATECALL` or `CALLCODE`.
    /// @dev Reverts with `StaticCallNotAllowed` when invoked under `STATICCALL`.
    /// @dev Reverts with `Unauthorized` when the caller is not the activation admin.
    /// @dev Reverts with `AlreadyActivated` when `feature` is already activated.
    ///
    /// @param feature Feature to activate.
    function activate(bytes32 feature) external;

    /// @notice Deactivates `feature`. Emits `FeatureDeactivated`.
    ///
    /// @dev Reverts with `DelegateCallNotAllowed` when invoked via `DELEGATECALL` or `CALLCODE`.
    /// @dev Reverts with `StaticCallNotAllowed` when invoked under `STATICCALL`.
    /// @dev Reverts with `Unauthorized` when the caller is not the activation admin.
    /// @dev Reverts with `AlreadyDeactivated` when `feature` is already deactivated.
    ///
    /// @param feature Feature to deactivate.
    function deactivate(bytes32 feature) external;
}
