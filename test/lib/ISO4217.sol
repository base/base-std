// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  ISO4217
/// @notice Format-only check for a stablecoin currency identifier:
///         exactly three uppercase ASCII letters (`A`–`Z`), matching
///         the shape of an ISO 4217 alphabetic code without enforcing
///         membership.
/// @dev    Membership is NOT validated. Any 3-letter uppercase string
///         is accepted (including codes that are not on ISO 4217 at
///         all). The narrower allowlist this previously encoded had
///         real maintenance cost — annual ISO amendments, lockstep
///         precompile updates for additions and withdrawals, judgement
///         calls on funds codes / metals / sentinels — for limited
///         marginal value: the field is self-declared, so any consumer
///         using `currency()` for authorization or routing already has
///         to layer its own issuer / contract allowlist on top of it.
///         Trimming the chain-side check to format-only keeps the
///         useful rejections (empty strings, wrong length, lowercase,
///         numerics, symbols like `"USDC"`) while removing that
///         maintenance surface.
///
///         See `docs/b20/stablecoin/currency-validation.md`. Any future
///         Rust precompile implementation must mirror this check exactly.
library ISO4217 {
    /// @notice Returns true iff `code` is exactly three bytes long and
    ///         every byte is in the uppercase ASCII range
    ///         `0x41`–`0x5A` (`A`–`Z`).
    function isValidFiatCode(string memory code) internal pure returns (bool) {
        bytes memory b = bytes(code);
        if (b.length != 3) return false;
        for (uint256 i = 0; i < 3; ++i) {
            bytes1 ch = b[i];
            if (ch < 0x41 || ch > 0x5A) return false;
        }
        return true;
    }
}
