// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title  IScaledUIAmount
/// @author Ethereum (ERC-8056)
///
/// @notice ERC-8056 core interface. A compliant token exposes an updatable, cosmetic
///         `uiMultiplier` (18-decimal WAD, `1e18 = 1.0`) that rescales the *displayed*
///         balance without minting, transferring, or rewriting any raw balance.
///
/// @dev    Interface ID: `0xa60bf13d`. The optional `TransferWithUIAmount` event is intentionally
///         not implemented; see `docs/B20/Asset.md` for the rationale.
interface IScaledUIAmount {
    /// @notice Emitted when the UI multiplier is updated.
    event UIMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, uint256 effectiveAtTimestamp);

    /// @notice Returns the current UI multiplier. Multiplier is represented with 18 decimals (`1e18 = 1.0`).
    /// @return Current UI multiplier.
    function uiMultiplier() external view returns (uint256);
}

/// @title  IScaledUIAmountNewUIMultiplier
/// @author Ethereum (ERC-8056)
///
/// @notice "Pending Multiplier" extension required by ERC-8056
///
/// @dev    Interface ID: `0x4bd27648`.
interface IScaledUIAmountNewUIMultiplier {
    /// @notice Returns the pending UI multiplier scheduled to take effect at `effectiveAt`.
    ///         Multiplier is represented with 18 decimals (`1e18 = 1.0`).
    /// @return Pending UI multiplier.
    function newUIMultiplier() external view returns (uint256);

    /// @notice Returns the timestamp at which the pending multiplier becomes effective.
    /// @return Effective-at timestamp.
    function effectiveAt() external view returns (uint256);
}

/// @title  IScaledUIAmountBalances
/// @author Ethereum (ERC-8056)
///
/// @notice ERC-8056 optional "Balances" extension for on-chain UI balance queries.
///
/// @dev    Interface ID: `0xd890fd71`.
interface IScaledUIAmountBalances {
    /// @notice Returns the UI-adjusted balance of an account.
    ///
    /// @param account Account whose UI-adjusted balance is being queried.
    ///
    /// @return UI-adjusted balance.
    function balanceOfUI(address account) external view returns (uint256);

    /// @notice Returns the UI-adjusted total supply.
    /// @return UI-adjusted total supply.
    function totalSupplyUI() external view returns (uint256);
}

/// @title  IScaledUIAmountConversion
/// @author Ethereum (ERC-8056)
///
/// @notice ERC-8056 optional "Conversion" extension: on-chain helpers for converting between raw
///         token amounts and their UI representation, using the effective (lazily-flipped)
///         multiplier. Integrators should treat raw on-chain amounts as canonical and call these
///         only at the display boundary; integer division truncates, so the round-trip is lossy.
///
/// @dev    Interface ID: `0x57854fc3`.
interface IScaledUIAmountConversion {
    /// @notice Converts a raw token amount to its UI representation.
    /// @param rawAmount Raw token amount to scale.
    /// @return UI amount at the effective multiplier.
    function toUIAmount(uint256 rawAmount) external view returns (uint256);

    /// @notice Converts a UI amount back to its raw token amount.
    /// @param uiAmount UI amount to convert back.
    /// @return Raw token amount at the effective multiplier.
    function fromUIAmount(uint256 uiAmount) external view returns (uint256);
}
