// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";

/// @notice Pins each feature id constant in `ActivationRegistryFeatureList` to
///         its canonical `keccak256("base.<feature>")` preimage.
///
/// @dev    These constants are the cross-language contract between the
///         Solidity mock surface and the Rust precompile's `ActivationFeature`
///         enum (`crates/common/precompiles/src/activation/storage.rs` in
///         base/base): both sides must hash the same string and arrive at the
///         same id. The pinning tests below catch silent drift in either
///         direction — a typo in the hex literal or in the string preimage
///         surfaces here before it can desync against the Rust source of
///         truth.
contract ActivationRegistryFeatureListTest is Test {
    /// @notice `B20_ASSET` equals `keccak256("base.b20_asset")`.
    function test_B20_ASSET_pinnedToKeccak() public pure {
        assertEq(
            ActivationRegistryFeatureList.B20_ASSET,
            keccak256("base.b20_asset"),
            "B20_ASSET must equal keccak256(\"base.b20_asset\")"
        );
    }

    /// @notice `POLICY_REGISTRY` equals `keccak256("base.policy_registry")`.
    function test_POLICY_REGISTRY_pinnedToKeccak() public pure {
        assertEq(
            ActivationRegistryFeatureList.POLICY_REGISTRY,
            keccak256("base.policy_registry"),
            "POLICY_REGISTRY must equal keccak256(\"base.policy_registry\")"
        );
    }

    /// @notice `B20_STABLECOIN` equals `keccak256("base.b20_stablecoin")`.
    function test_B20_STABLECOIN_pinnedToKeccak() public pure {
        assertEq(
            ActivationRegistryFeatureList.B20_STABLECOIN,
            keccak256("base.b20_stablecoin"),
            "B20_STABLECOIN must equal keccak256(\"base.b20_stablecoin\")"
        );
    }
}
