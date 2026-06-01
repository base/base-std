// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IActivationRegistry} from "./interfaces/IActivationRegistry.sol";
import {IPolicyRegistry} from "./interfaces/IPolicyRegistry.sol";
import {IB20Factory} from "./interfaces/IB20Factory.sol";

/// @title StdPrecompiles
/// @notice Address constants for Base's singleton precompiles, each paired with an interface-typed
///         handle (e.g. `StdPrecompiles.B20_FACTORY.createB20(...)`).
library StdPrecompiles {
    address internal constant B20_FACTORY_ADDRESS = 0xB20f000000000000000000000000000000000000;
    address internal constant POLICY_REGISTRY_ADDRESS = 0x8453000000000000000000000000000000000002;
    address internal constant ACTIVATION_REGISTRY_ADDRESS = 0x8453000000000000000000000000000000000001;

    IB20Factory internal constant B20_FACTORY = IB20Factory(B20_FACTORY_ADDRESS);
    IPolicyRegistry internal constant POLICY_REGISTRY = IPolicyRegistry(POLICY_REGISTRY_ADDRESS);
    IActivationRegistry internal constant ACTIVATION_REGISTRY = IActivationRegistry(ACTIVATION_REGISTRY_ADDRESS);
}
