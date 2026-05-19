// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title PauseVectors
/// @notice Helpers for constructing the pause bitmask passed to
///         `IB20.pause(uint256 vectors)`. Each `PausableFeature` value
///         corresponds to a single bit position; `toPauseVector` OR's
///         a set of features into the combined bitmask the token
///         expects.
library PauseVectors {
    /// @notice Pausable operation classes on a B-20 token. Bit position
    ///         is the enum ordinal. The enum is append-only across
    ///         protocol versions, so existing ordinals are stable.
    enum PausableFeature {
        TRANSFER,
        MINT,
        BURN,
        REDEEM
    }

    /// @notice Combines `features` into the bitmask passed to
    ///         `IB20.pause`. Duplicate entries are idempotent (a feature
    ///         may appear multiple times without changing the result).
    ///         Returns `0` for an empty array.
    function toPauseVector(PausableFeature[] memory features) internal pure returns (uint256 vectors) {
        for (uint256 i = 0; i < features.length; i++) {
            vectors |= uint256(1) << uint256(features[i]);
        }
    }
}
