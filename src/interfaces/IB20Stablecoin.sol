// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title  IB20Stablecoin
/// @notice B-20 variant for fiat-pegged stablecoins. Inherits the full
///         `IB20` surface and adds one immutable `currency()` identifier.
/// @dev    Scope is fiat-only; commodity-backed and basket tokens belong
///         elsewhere. See `docs/b20/stablecoin/currency-validation.md` for the inclusion /
///         exclusion lists, regulatory framing, and trust model.
interface IB20Stablecoin is IB20 {
    /// @notice The ISO 4217 fiat code this stablecoin tracks
    ///         (e.g. `"USD"`, `"EUR"`, `"JPY"`). Set at creation,
    ///         immutable thereafter.
    /// @dev    Self-declared and not verified by the contract. See
    ///         `docs/b20/stablecoin/currency-validation.md` for the validated value space
    ///         and what consumers must layer on top.
    function currency() external view returns (string memory);
}
