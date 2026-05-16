// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IActivationRegistry} from "../interfaces/IActivationRegistry.sol";

/// @title ActivationRegistry
/// @notice Library for interacting with the ActivationRegistry precompile.
///         Exposes the precompile address as a typed constant and provides
///         helper utilities for feature-gated contracts.
///
/// @dev    All calls route through `PRECOMPILE`. Callers should handle the
///         case where the precompile does not exist (pre-Beryl forks) by
///         catching reverts or checking the hardfork version before calling.
library ActivationRegistry {
    /*//////////////////////////////////////////////////////////////
                             PRECOMPILE ADDRESS
    //////////////////////////////////////////////////////////////*/

    /// @notice Typed reference to the ActivationRegistry precompile.
    /// @dev    Available from the Beryl hardfork.
    IActivationRegistry internal constant PRECOMPILE =
        IActivationRegistry(0x84530000000000000000000000000000000000ff);

    /*//////////////////////////////////////////////////////////////
                            KNOWN FEATURE IDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Feature ID gating security-token creation.
    ///         When enabled, authorized factories may create tokenized equity
    ///         instruments via the Tangor protocol. When disabled, any
    ///         attempt to create a asset token reverts.
    bytes32 internal constant SECURITIES_TOKEN_CREATION =
        0x89e4523f0886ce01d76094212ed707081da92a45221e22c15c5689be470db63e;

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts with `IActivationRegistry.FeatureNotEnabled` if
    ///         `feature` is not yet enabled. Intended as a one-line guard
    ///         at the top of feature-gated functions.
    /// @param feature The feature ID to assert is enabled.
    function assertEnabled(bytes32 feature) internal view {
        if (!PRECOMPILE.isEnabled(feature)) {
            revert IActivationRegistry.FeatureNotEnabled(feature);
        }
    }
}