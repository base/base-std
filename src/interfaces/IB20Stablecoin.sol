// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title IB20Stablecoin
/// @notice A B-20 token variant for value-pegged tokens (USD, EUR, XAU, etc.).
///         Inherits the full `IB20` surface and adds a single
///         immutable `currency()` identifier for routing, categorization,
///         and wallet display.
///
/// @dev    Per the team PRD, stablecoin-specific features that earlier
///         drafts attempted to enshrine here have been moved out of the
///         protocol surface entirely:
///
///         - **Per-minter rate limiting** lives in EVM periphery
///           contracts (a stablecoin issuer's own controller / wrapper
///           contract that holds `MINT_ROLE` and enforces per-caller
///           quotas before invoking `mint` on the precompile). The
///           Bridge `TIP20Controller` pattern and the CDP Custom
///           Stablecoin pattern are both expressible this way.
///         - **ERC-3009 transfer-with-authorization** is not on the
///           default surface. Stablecoin issuers that need gasless
///           payment flows can layer it via periphery contracts (or
///           rely on EIP-2612 permit, which IS on the default surface,
///           plus call-batching on the wallet side).
///         - **Sanctions seizure** ("force-burn from blocked addresses")
///           is not on the default surface either. CCS uses the
///           "freeze, never seize" philosophy and never burns;
///           stablecoin issuers that need seizure flows do them via
///           periphery contracts that hold roles for the underlying
///           operations.
///
///         Compliance (sanctions, jurisdiction restrictions, KYC) is
///         delegated to the policy engine via `IB20.transferPolicyId`.
///         Issuers point their stablecoin at a compound policy with the
///         appropriate sender, recipient, mint-recipient, and redeemer
///         slots configured per their compliance regime.
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
