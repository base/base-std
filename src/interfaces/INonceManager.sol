// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title INonceManager
///
/// @notice Singleton precompile managing the EIP-8130 two-dimensional nonces that enable
///         concurrent account-abstraction transaction execution. Each `(account, nonceKey)`
///         channel carries its own independently-ordered sequence nonce. Nonce key `0` is the
///         protocol nonce; it is held in account state and is not served by this precompile.
interface INonceManager {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice The precompile was invoked via `DELEGATECALL` or `CALLCODE`.
    error DelegateCallNotAllowed();

    /// @notice Nonce key `0` is the protocol nonce and is not served by this precompile;
    ///         read it from account state instead.
    error ProtocolNonceNotSupported();

    /// @notice Nonce key `0` is reserved for the protocol nonce and cannot be incremented here.
    error InvalidNonceKey();

    /// @notice The `(account, nonceKey)` channel nonce is already at its maximum value.
    error NonceOverflow();

    /// @notice An expiring nonce's `validBefore` is outside the allowed `(now, now + maxExpiry]` window.
    error InvalidExpiringNonceExpiry();

    /// @notice An expiring-nonce replay hash has already been recorded and has not yet expired.
    error ExpiringNonceReplay();

    /// @notice The expiring-nonce set is full of unexpired entries and cannot accept more.
    error ExpiringNonceSetFull();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the 2D nonce for `(account, nonceKey)` is incremented to `newNonce`.
    event NonceIncremented(address indexed account, uint256 indexed nonceKey, uint64 newNonce);

    /*//////////////////////////////////////////////////////////////
                              NONCE QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current 2D nonce for `account` at `nonceKey`. A never-used channel
    ///         reads as `0`.
    ///
    /// @dev Reverts with `ProtocolNonceNotSupported` for nonce key `0`.
    ///
    /// @param account  Account whose channel nonce is being queried.
    /// @param nonceKey Non-zero nonce channel to query.
    ///
    /// @return The current sequence nonce for the channel.
    function getNonce(address account, uint256 nonceKey) external view returns (uint64);
}
