// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IActivationRegistry} from "./interfaces/IActivationRegistry.sol";
import {IPolicyRegistry} from "./interfaces/IPolicyRegistry.sol";
import {IB20Factory} from "./interfaces/IB20Factory.sol";
import {ITransactionContext} from "./interfaces/ITransactionContext.sol";
import {INonceManager} from "./interfaces/INonceManager.sol";

/// @title StdPrecompiles
/// @notice Address constants for Base's singleton precompiles, each paired with an interface-typed
///         handle (e.g. `StdPrecompiles.B20_FACTORY.createB20(...)`).
library StdPrecompiles {
    address internal constant B20_FACTORY_ADDRESS = 0xB20f000000000000000000000000000000000000;
    address internal constant POLICY_REGISTRY_ADDRESS = 0x8453000000000000000000000000000000000002;
    address internal constant ACTIVATION_REGISTRY_ADDRESS = 0x8453000000000000000000000000000000000001;
    // EIP-8130 system precompiles, in the 0x8130... (EIP number) namespace.
    address internal constant NONCE_MANAGER_ADDRESS = 0x813000000000000000000000000000000000aa01;
    address internal constant TX_CONTEXT_ADDRESS = 0x813000000000000000000000000000000000aa02;

    IB20Factory internal constant B20_FACTORY = IB20Factory(B20_FACTORY_ADDRESS);
    IPolicyRegistry internal constant POLICY_REGISTRY = IPolicyRegistry(POLICY_REGISTRY_ADDRESS);
    IActivationRegistry internal constant ACTIVATION_REGISTRY = IActivationRegistry(ACTIVATION_REGISTRY_ADDRESS);
    ITransactionContext internal constant TX_CONTEXT = ITransactionContext(TX_CONTEXT_ADDRESS);
    INonceManager internal constant NONCE_MANAGER = INonceManager(NONCE_MANAGER_ADDRESS);
}
