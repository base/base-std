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
