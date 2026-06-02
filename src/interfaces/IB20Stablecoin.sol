// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title  IB20Stablecoin
/// @notice B-20 variant for fiat-pegged stablecoins. Extends `IB20` with an immutable `currency()` code.
interface IB20Stablecoin is IB20 {
    /// @notice The currency code this stablecoin tracks (e.g. `"USD"`, `"EUR"`, `"JPY"`).
    /// @return Currency code.
    function currency() external view returns (string memory);
}
