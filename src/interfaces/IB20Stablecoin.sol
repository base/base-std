// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title  IB20Stablecoin
/// @notice B-20 variant for fiat-pegged stablecoins. Inherits the full
///         `IB20` surface and adds one immutable `currency()` identifier.
interface IB20Stablecoin is IB20 {
    /// @notice The currency identifier this stablecoin tracks
    ///         (e.g. `"USD"`, `"EUR"`, `"JPY"`). Set at creation,
    ///         immutable thereafter. Uppercase ASCII letters (`A`–`Z`);
    ///         self-declared and not verified by the contract.
    function currency() external view returns (string memory);
}
