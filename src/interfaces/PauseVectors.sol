// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title PauseVectors
/// @notice Bit positions for the granular pause bitfield used by `pause`
///         and `paused` on `IDefaultToken` and its variants.
///
///         A token's `pause(uint256 vectors)` function accepts a bitmask
///         of vectors to pause; multiple calls are additive (each call
///         OR's its argument into the current paused state). `unpause()`
///         clears all paused vectors at once. `paused()` returns the
///         current bitmask, and `isPaused(vector)` returns whether a
///         specific vector is set.
///
///         Bit positions are append-only across protocol versions and
///         shared across token variants. Default-token vectors live in
///         bits 0..15; security-variant additions would live in bits
///         16..23; stablecoin-variant additions in bits 24..31.
library PauseVectors {
    /*//////////////////////////////////////////////////////////////
                       Default-token vectors (0..15)
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses `mint` and `mintWithMemo`. Issuance is halted while
    ///         this bit is set.
    uint256 internal constant MINT = 1 << 0;

    /// @notice Pauses `burn` and `burnWithMemo`. Holders cannot destroy
    ///         their own balance via `burn` while this bit is set.
    uint256 internal constant BURN = 1 << 1;

    /// @notice Pauses `transfer`, `transferFrom`, and the `*WithMemo`
    ///         siblings. Holder-to-holder movement is halted while this
    ///         bit is set. Mint, burn, and redeem vectors are independent.
    uint256 internal constant TRANSFER = 1 << 2;

    /// @notice Pauses `redeem` and `redeemWithMemo`. Holders cannot
    ///         redeem their balance for off-chain settlement while this
    ///         bit is set. Independent of the `BURN` vector even though
    ///         both operations destroy supply: redeem implies an
    ///         off-chain claim, burn does not.
    uint256 internal constant REDEEM = 1 << 3;
}
