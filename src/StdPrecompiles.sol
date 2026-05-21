// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IActivationRegistry} from "./interfaces/IActivationRegistry.sol";
import {IPolicyRegistry} from "./interfaces/IPolicyRegistry.sol";
import {ITokenFactory} from "./interfaces/ITokenFactory.sol";

/// @title Standard Precompiles Library for Base
/// @notice Address constants for Base's singleton precompiles, paired
///         with interface-typed handles so callers can interact with
///         them directly (e.g. `StdPrecompiles.TOKEN_FACTORY.createToken(...)`).
library StdPrecompiles {
    /// @dev The `0xB20F` prefix mirrors the `0xB2` B-20 token prefix while staying
    ///      disjoint (B-20 tokens have `0x00` at byte [1]; the factory has `0x0F`),
    ///      so `isB20(TOKEN_FACTORY_ADDRESS)` returns false unambiguously. The
    ///      trailing `0x0F` byte echoes the prefix for visual symmetry.
    address internal constant TOKEN_FACTORY_ADDRESS = 0xb20F00000000000000000000000000000000000f;
    address internal constant POLICY_REGISTRY_ADDRESS = 0xb030000000000000000000000000000000000000;
    address internal constant ACTIVATION_REGISTRY_ADDRESS = 0x84530000000000000000000000000000000000ff;

    ITokenFactory internal constant TOKEN_FACTORY = ITokenFactory(TOKEN_FACTORY_ADDRESS);
    IPolicyRegistry internal constant POLICY_REGISTRY = IPolicyRegistry(POLICY_REGISTRY_ADDRESS);
    IActivationRegistry internal constant ACTIVATION_REGISTRY = IActivationRegistry(ACTIVATION_REGISTRY_ADDRESS);
}
