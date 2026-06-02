// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Constants} from "src/lib/B20Constants.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";
import {MockB20SecurityStorage} from "test/lib/mocks/MockB20Storage.sol";

/// @notice Exhaustive layout spec for the `base.b20.security` namespace.
///
/// @dev    Mirrors `B20FullLayout.t.sol`'s pattern for the security
///         variant's added namespace. Populates non-default values in
///         every field via the public `IB20Security` surface, then asserts
///         the raw slot bytes at each absolute slot via `vm.load`.
///
///         The base-namespace layout itself (`base.b20`, slots 0..14) is
///         covered by `B20FullLayout.t.sol`. Per-mutator base behavior on
///         the security variant is exercised through `B20SecurityTest`-
///         derived test contracts.
contract B20SecurityFullLayoutTest is B20SecurityTest {
    // ---------- Distinct marker values per field ----------

    /// @dev Non-WAD multiplier so the slot value is observably different from
    ///      both zero (the "unwritten = WAD" default) and WAD itself.
    uint256 internal constant MULTIPLIER_MARKER = 2.5e18;

    string internal constant FIGI_VALUE = "BBG000B9XRY4";
    string internal constant ANNOUNCEMENT_ID = "layout-pin-announcement";

    /// @notice Cross-cuts every field of the security-variant namespace in
    ///         one populated snapshot.
    /// @dev    Field coverage for `base.b20.security` (slots 0..3):
    ///         - 0: decimals (factory-written at creation)
    ///         - 1: multiplier
    ///         - 2: usedAnnouncementIds[id]
    ///         - 3: identifiers[identifierType]  (FIGI mutated)
    function test_b20SecurityLayout_success_populatedSnapshotMatchesAllSlots() public {
        // ---------- Populate ----------
        _populate();

        address tokenAddr = address(token);

        // ---------- decimals (slot 0) ----------
        // The default `_securityParams()` helper passes MIN_ASSET_DECIMALS (6),
        // and the factory writes that as a one-word `uint256` (low byte).
        assertEq(
            uint256(vm.load(tokenAddr, MockB20SecurityStorage.decimalsSlot())),
            uint256(B20Constants.MIN_ASSET_DECIMALS),
            "security slot 0: decimals must hold the factory-written value"
        );

        // ---------- multiplier (slot 1) ----------
        assertEq(
            uint256(vm.load(tokenAddr, MockB20SecurityStorage.multiplierSlot())),
            MULTIPLIER_MARKER,
            "security slot 1: multiplier must hold the written value"
        );

        // ---------- usedAnnouncementIds[id] (slot 2, hashed by id) ----------
        // Slot resolves to keccak256(abi.encodePacked(id, baseSlot)). Solidity
        // stores a `bool true` as a one-word `uint256(1)`.
        assertEq(
            uint256(vm.load(tokenAddr, MockB20SecurityStorage.usedAnnouncementIdSlot(ANNOUNCEMENT_ID))),
            uint256(1),
            "security slot 2: usedAnnouncementIds[id] must be true after announce"
        );

        // ---------- identifiers[identifierType] (slot 3, hashed by type) ----------
        // The factory does not seed any identifier at creation, so a fresh token's
        // ISIN slot is empty. The post-creation FIGI write is pinned to the
        // canonical string-field encoding at its derived slot.
        assertEq(
            vm.load(tokenAddr, MockB20SecurityStorage.identifierSlot(IDENTIFIER_ISIN)),
            bytes32(0),
            "security slot 3: identifiers[ISIN] must remain zero (factory seeds no identifiers)"
        );
        assertEq(
            vm.load(tokenAddr, MockB20SecurityStorage.identifierSlot(IDENTIFIER_FIGI)),
            _expectedStringFieldSlot(FIGI_VALUE),
            "security slot 3: identifiers[FIGI] must hold the post-creation short-string encoding"
        );
    }

    /// @notice Populates the security variant with non-default values
    ///         across every field of the added namespace. Centralized so
    ///         the layout test reads as a single assertion sweep with no
    ///         interleaved mutations.
    function _populate() internal {
        // multiplier: write the non-WAD marker via the public surface.
        _updateMultiplier(MULTIPLIER_MARKER);
        // identifiers[FIGI]: post-creation operator write. The factory does not
        // seed any identifier at creation; ISIN, CUSIP, etc. all default to empty.
        _grantOperator();
        vm.prank(operator);
        security().updateSecurityIdentifier(IDENTIFIER_FIGI, FIGI_VALUE);
        // usedAnnouncementIds[ANNOUNCEMENT_ID]: flip via announce.
        _announce(ANNOUNCEMENT_ID);
    }
}
