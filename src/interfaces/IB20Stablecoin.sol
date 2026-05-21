// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title IB20Stablecoin
/// @notice A B-20 token variant for tokens designed to track the value
///         of a national fiat currency. Inherits the full `IB20`
///         surface and adds a single immutable `currency()` identifier
///         used by downstream tooling (indexers, wallets, and any
///         protocol that wants to group tokens by the asset they peg
///         to) to categorize the token.
///
/// @dev    **Scope and industry-naming notes.** "Stablecoin" is used
///         in industry and regulation to describe a wider set of
///         instruments than this variant accepts. The Financial
///         Stability Board and the Bank for International Settlements
///         define a stablecoin broadly as "a crypto-asset that aims
///         to maintain a stable value relative to a specified asset,
///         or a pool or basket of assets" — which covers fiat,
///         commodities, baskets, and other crypto. This variant
///         deliberately scopes to the narrower category, aligning
///         with the regulators that have sub-divided the term:
///
///         - **EU MiCA** defines *E-Money Tokens (EMTs)* — single fiat
///           currency, our scope — as a distinct category from
///           *Asset-Referenced Tokens (ARTs)*, which cover
///           commodities, baskets, and multi-currency pegs.
///         - **MAS Singapore** defines *Single-Currency Stablecoins
///           (SCS)* — pegged to one G10 fiat currency — as the
///           regulated category; other asset-referenced tokens fall
///           outside the SCS framework.
///         - **US payment-stablecoin legislative proposals** (GENIUS
///           Act, Clarity for Payment Stablecoins Act, and
///           predecessors) generally define "payment stablecoin" as
///           fiat-backed only.
///
///         This variant lines up with the EMT / SCS / payment-
///         stablecoin definition specifically. Concretely:
///
///         - **Commodity-backed tokens** that market themselves as
///           "stablecoins" — e.g. PAXG, XAUT (gold-backed) — are
///           structurally claims on a vault and are securities-shaped
///           instruments. They belong on the `IB20Security` variant,
///           not here.
///         - **Crypto-collateralized stablecoins** that still peg to
///           a fiat currency — e.g. DAI, LUSD, crvUSD — fit this
///           variant. The mechanism backing the peg (custodial
///           reserves vs. on-chain collateral vs. T-bills) is
///           irrelevant to `currency()`; what matters is what the
///           token tracks. If it tracks USD, declare `"USD"`.
///
///         This variant prioritizes the majority fiat-pegged use
///         case at the cost of excluding edge cases that other B-20
///         variants are better suited to serve.
interface IB20Stablecoin is IB20 {
    /*//////////////////////////////////////////////////////////////
                          CURRENCY IDENTIFIER
    //////////////////////////////////////////////////////////////*/

    /// @notice The national fiat currency this stablecoin is designed
    ///         to track, expressed as an active ISO 4217 alphabetic
    ///         code (e.g. `"USD"`, `"EUR"`, `"JPY"`). Set at creation
    ///         by the factory; immutable thereafter. Two stablecoins
    ///         tracking the same currency return byte-identical values.
    ///
    /// @dev    **Value space.** The factory validates this field
    ///         against a hardcoded allowlist of active ISO 4217 codes
    ///         registered as national means of payment. Any value
    ///         outside that allowlist reverts at creation with
    ///         `ITokenFactory.InvalidCurrency(code)`; see
    ///         `ISO4217.isValidFiatCode` for the canonical list.
    ///         Specifically excluded:
    ///         - **ISO 4217 X-prefix codes** (XAU/XAG/XPT/XPD precious
    ///           metals, XBA-XBD bond market units, XDR IMF special
    ///           drawing rights, XSU sucre, XUA ADB unit of account,
    ///           XTS test code, XXX no-currency sentinel). These are
    ///           reserved by ISO 4217 for non-currency uses. Tokens
    ///           backed by precious metals or other commodities are
    ///           securities-shaped instruments and belong on the
    ///           `IB20Security` variant.
    ///         - **Crypto tickers** (BTC, ETH, etc.) and any other
    ///           free-form symbol — out of scope for this variant.
    ///
    ///         **Trust model.** This field is the issuer's *self-
    ///         declared* peg. The factory enforces format and
    ///         membership in the ISO 4217 fiat allowlist; it does NOT
    ///         verify the token is actually backed by, or actually
    ///         tracking, the named currency. Any protocol that consumes
    ///         `currency()` to make an authorization or categorization
    ///         decision MUST still apply its own allowlist or trust
    ///         resolution on top — typically an issuer / contract
    ///         allowlist maintained by the consumer. What this field
    ///         provides is a standardized, immutable, machine-readable
    ///         identifier that consumer-side allowlists can be
    ///         organized around (e.g. "must be on my issuer allowlist
    ///         AND `currency() == \"USD\"`"), not the allowlist itself.
    ///
    ///         **Immutability.** No setter exists. The identifier is
    ///         fixed at construction by the factory and cannot be
    ///         changed afterward; mutability would let an admitted
    ///         token silently switch what it claims to represent and
    ///         break any consumer that built admission logic on top of
    ///         the field.
    function currency() external view returns (string memory);
}
