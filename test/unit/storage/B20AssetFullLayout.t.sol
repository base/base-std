// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";
import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @notice Exhaustive layout spec for the `base.b20.asset` namespace.
///
/// @dev    Mirrors `B20FullLayout.t.sol`'s pattern for the asset
///         variant's added namespace. Populates non-default values in
///         every field via the public `IB20Asset` surface, then asserts
///         the raw slot bytes at each absolute slot via `vm.load`.
///
///         The base-namespace layout itself (`base.b20`, slots 0..14) is
///         covered by `B20FullLayout.t.sol`. Per-mutator base behavior on
///         the asset variant is exercised through `B20AssetTest`-
///         derived test contracts.
contract B20AssetFullLayoutTest is B20AssetTest {
    // ---------- Distinct marker values per field ----------

    /// @dev Non-WAD multiplier so the slot value is observably different from
    ///      both zero (the "unwritten = WAD" default) and WAD itself.
    uint256 internal constant MULTIPLIER_MARKER = 2.5e18;

    string internal constant REFERENCE_VALUE = "REF-2024-001";
    string internal constant ANNOUNCEMENT_ID = "layout-pin-announcement";

    /// @notice Cross-cuts every field of the asset-variant namespace in
    ///         one populated snapshot.
    /// @dev    Field coverage for `base.b20.asset` (slots 0..3):
    ///         - 0: decimals (factory-written at creation)
    ///         - 1: multiplier
    ///         - 2: usedAnnouncementIds[id]
    ///         - 3: extraMetadata[key]  (one example key mutated; the other
    ///              left empty to confirm the factory seeds no entries)
    function test_b20AssetLayout_success_populatedSnapshotMatchesAllSlots() public {
        // ---------- Populate ----------
        _populate();

        address tokenAddr = address(token);

        // ---------- decimals (slot 0) ----------
        // The default `_assetParams()` helper passes MIN_ASSET_DECIMALS (6),
        // and the factory writes that as a one-word `uint256` (low byte).
        assertEq(
            uint256(vm.load(tokenAddr, MockB20AssetStorage.decimalsSlot())),
            uint256(B20Constants.MIN_ASSET_DECIMALS),
            "asset slot 0: decimals must hold the factory-written value"
        );

        // ---------- multiplier (slot 1) ----------
        assertEq(
            uint256(vm.load(tokenAddr, MockB20AssetStorage.multiplierSlot())),
            MULTIPLIER_MARKER,
            "asset slot 1: multiplier must hold the written value"
        );

        // ---------- usedAnnouncementIds[id] (slot 2, hashed by id) ----------
        // Slot resolves to keccak256(abi.encodePacked(id, baseSlot)). Solidity
        // stores a `bool true` as a one-word `uint256(1)`.
        assertEq(
            uint256(vm.load(tokenAddr, MockB20AssetStorage.usedAnnouncementIdSlot(ANNOUNCEMENT_ID))),
            uint256(1),
            "asset slot 2: usedAnnouncementIds[id] must be true after announce"
        );

        // ---------- extraMetadata[key] (slot 3, hashed by key) ----------
        // The factory does not seed any entry at creation, so a fresh token's
        // unwritten key reads as empty. The post-creation write is pinned to
        // the canonical string-field encoding at its derived slot.
        assertEq(
            vm.load(tokenAddr, MockB20AssetStorage.extraMetadataSlot(METADATA_EXAMPLE_1)),
            bytes32(0),
            "asset slot 3: extraMetadata[example_1] must remain zero (factory seeds no entries)"
        );
        assertEq(
            vm.load(tokenAddr, MockB20AssetStorage.extraMetadataSlot(METADATA_EXAMPLE_3)),
            _expectedStringFieldSlot(REFERENCE_VALUE),
            "asset slot 3: extraMetadata[example_3] must hold the post-creation short-string encoding"
        );
    }

    /// @notice Populates the asset variant with non-default values
    ///         across every field of the added namespace. Centralized so
    ///         the layout test reads as a single assertion sweep with no
    ///         interleaved mutations.
    function _populate() internal {
        // multiplier: write the non-WAD marker via the public surface.
        _updateMultiplier(MULTIPLIER_MARKER);
        // extraMetadata[example_3]: post-creation metadata-admin write. The
        // factory does not seed any entry at creation; every other key
        // defaults to empty.
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        asset().updateExtraMetadata(METADATA_EXAMPLE_3, REFERENCE_VALUE);
        // usedAnnouncementIds[ANNOUNCEMENT_ID]: flip via announce.
        _announce(ANNOUNCEMENT_ID);
    }
}
