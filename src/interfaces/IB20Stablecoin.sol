// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title IB20Stablecoin
/// @notice A B-20 token variant for value-pegged tokens (USD, EUR, XAU, etc.).
///         Inherits the full `IB20` surface and adds a single
///         immutable `currency()` identifier for routing, categorization,
///         and wallet display.
///
interface IB20Stablecoin is IB20 {
    /*//////////////////////////////////////////////////////////////
                          CURRENCY IDENTIFIER
    //////////////////////////////////////////////////////////////*/

    /// @notice The reference asset this stablecoin is designed to track.
    ///         Set at creation by the factory; immutable thereafter.
    /// @dev    Two stablecoins tracking the same asset return the same
    ///         identifier. Conventions:
    ///         - ISO-4217 codes for fiat / commodity references: "USD",
    ///           "EUR", "JPY", "XAU" (gold), "XAG" (silver).
    ///         - Symbol for non-ISO references: "BTC", "ETH" (for tokens
    ///           tracking the price of those assets).
    ///         - The token's own symbol if it tracks no external reference
    ///           (governance, utility tokens that nonetheless want the
    ///           stablecoin variant for the operational surface).
    function currency() external view returns (string memory);
}
