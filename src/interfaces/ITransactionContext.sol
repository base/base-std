// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title ITransactionContext
///
/// @notice Singleton precompile exposing the resolved context of the in-flight EIP-8130
///         account-abstraction transaction: its sender, payer, and the actor id resolved while
///         authenticating the sender. On non-EIP-8130 transactions the context is not populated and
///         the getters fall back to `tx.origin`: `getTransactionSender` and `getTransactionPayer`
///         return `tx.origin`, and `getTransactionSenderActorId` returns `bytes32(bytes20(tx.origin))`.
interface ITransactionContext {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice The precompile was invoked via `DELEGATECALL` or `CALLCODE`.
    error DelegateCallNotAllowed();

    /*//////////////////////////////////////////////////////////////
                            CONTEXT QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The resolved sender of the in-flight transaction. Never reverts; returns
    ///         `tx.origin` outside of an EIP-8130 transaction.
    ///
    /// @return The resolved sender, or `tx.origin`.
    function getTransactionSender() external view returns (address);

    /// @notice The resolved payer of the in-flight transaction, equal to the sender when the
    ///         transaction is self-paying. Never reverts; returns `tx.origin` outside of an
    ///         EIP-8130 transaction.
    ///
    /// @return The resolved payer, or `tx.origin`.
    function getTransactionPayer() external view returns (address);

    /// @notice The actor id resolved while authenticating the sender of the in-flight
    ///         transaction. Never reverts; returns `bytes32(bytes20(tx.origin))` outside of an
    ///         EIP-8130 transaction.
    ///
    /// @return The resolved sender actor id, or `bytes32(bytes20(tx.origin))`.
    function getTransactionSenderActorId() external view returns (bytes32);
}
