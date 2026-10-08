// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IBaseTime} from "./interfaces/IBaseTime.sol";

/// @title StdPredeploys
/// @notice Address constants for Base's predeploys, each paired with an interface-typed handle
///         (e.g. `StdPredeploys.BASE_TIME.timestampMs()`). Predeploys are EVM bytecode at `0x4200…`
///         addresses, unlike the native precompiles in `StdPrecompiles`.
library StdPredeploys {
    address internal constant BASE_TIME_ADDRESS = 0x4200000000000000000000000000000000000030;

    IBaseTime internal constant BASE_TIME = IBaseTime(BASE_TIME_ADDRESS);
}
