// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IDefaultToken} from "./IDefaultToken.sol";

/// @title IStablecoin
/// @notice A B-20 token variant for value-pegged tokens (USD, EUR, XAU, etc.).
///         Inherits the full IDefaultToken surface; adds an immutable
///         currency-identifier accessor so integrators (DEXes, fee-routing
///         systems, wallets, indexers) can categorize and route the token
///         without per-issuer configuration.
/// @dev    Stablecoin-specific compliance (sanctions, jurisdiction restrictions,
///         brokerage gating, etc.) is delegated to the policy engine via
///         IDefaultToken's transferPolicyId, not implemented here. Stablecoin
///         issuers are expected to point their token at a compound policy with
///         the appropriate sender / recipient / mint-recipient rules.
interface IStablecoin is IDefaultToken {
    /// @notice The reference asset this stablecoin is designed to track. Set
    ///         at creation by the factory; immutable thereafter.
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
