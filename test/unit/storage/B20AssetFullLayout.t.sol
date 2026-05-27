// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Asset} from "src/interfaces/IB20Asset.sol";
import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {StdPrecompiles} from "src/StdPrecompiles.sol";

import {B20AssetTest} from "test/lib/B20AssetTest.sol";
import {MockB20Asset} from "test/lib/mocks/MockB20Asset.sol";
import {MockB20AssetStorage, MockB20RedeemStorage} from "test/lib/mocks/MockB20Storage.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

/// @notice Exhaustive layout spec for the `base.b20.asset` and
///         `base.b20.redeem` namespaces.
///
/// @dev    Mirrors `B20FullLayout.t.sol`'s pattern for the security
///         variant's two added namespaces. Populates non-default values
///         in every field via the public `IB20Asset` surface, then
///         asserts the raw slot bytes at each absolute slot via
///         `vm.load` and explicit bit-position math.
///
///         The base-namespace layout itself (`base.b20`, slots 0..14)
///         is covered by `B20FullLayout.t.sol`. Per-mutator base
///         behavior on the asset variant is exercised through
///         `B20AssetTest`-derived test contracts.
///
///         **Why explicit bit-position math instead of codec helpers?**
///         The codec helpers in `MockB20RedeemStorage` (when they
///         exist) and inline shifts elsewhere encode the SAME bit
///         positions the Rust impl must reproduce. Asserting via the
///         codec would let codec bugs hide each other ("the codec says
///         the slot says what we wrote, even if both are wrong"). The
///         layout pin reads the raw slot and asserts exact bit ranges,
///         so the test grounds out at the bytes — the codec is then
///         separately verified by roundtrip tests under
///         `MockB20SlotHelpers.t.sol` / `MockPolicyRegistrySlotHelpers.t.sol`.
///         Both signals together prove "the layout is what we think AND
///         the codec matches that layout".
contract B20AssetFullLayoutTest is B20AssetTest {
    // ---------- Distinct marker values per lane / field ----------

    /// @dev Marker for the REDEEM_SENDER_POLICY lane. Set in `_populate`
    ///      by creating a real custom policy in the registry, so the ID
    ///      satisfies `updatePolicy`'s `policyExists` precondition.
    ///      Synthetic uint64 markers (e.g. `0x5555...`) would be rejected.
    uint64 internal redeemSenderMarker;

    /// @dev Non-WAD ratio so the slot value is observably different from
    ///      both zero (the "unwritten = WAD" default) and WAD itself.
    uint256 internal constant SHARE_RATIO_MARKER = 2.5e18;

    /// @dev Per-mutation `minimumRedeemable`. Distinct from the
    ///      bootstrap-seeded value below so the post-mutation slot is
    ///      observably the post-mutation value, not the seeded one.
    uint256 internal constant MINIMUM_REDEEMABLE_MARKER = 7e18;

    string internal constant FIGI_VALUE = "BBG000B9XRY4";
    string internal constant ANNOUNCEMENT_ID = "layout-pin-announcement";

    /// @notice Cross-cuts every field of the two security-variant
    ///         namespaces in one populated snapshot.
    /// @dev    Field coverage:
    ///
    ///         `base.b20.asset` (slots 0..2):
    ///         - 0: sharesToTokensRatio
    ///         - 1: usedAnnouncementIds[id]
    ///         - 2: identifiers[identifierType]  (ISIN seeded + FIGI mutated)
    ///
    ///         `base.b20.redeem` (slots 0..1):
    ///         - 0: minimumRedeemable
    ///         - 1: redeemPolicyIds  (lane 0 = REDEEM_SENDER_POLICY,
    ///              lanes 1..3 reserved)
    function test_b20SecurityLayout_success_populatedSnapshotMatchesAllSlots() public {
        // ---------- Populate ----------
        _populate();

        address tokenAddr = address(token);

        // ============================================================
        //                  base.b20.asset namespace
        // ============================================================

        // ---------- sharesToTokensRatio (slot 0) ----------
        assertEq(
            uint256(vm.load(tokenAddr, MockB20AssetStorage.sharesToTokensRatioSlot())),
            SHARE_RATIO_MARKER,
            "security slot 0: sharesToTokensRatio must hold the written ratio"
        );

        // ---------- usedAnnouncementIds[id] (slot 1, hashed by id) ----------
        // Slot resolves to keccak256(abi.encodePacked(id, baseSlot)). Solidity
        // stores a `bool true` as a one-word `uint256(1)`.
        assertEq(
            uint256(vm.load(tokenAddr, MockB20AssetStorage.usedAnnouncementIdSlot(ANNOUNCEMENT_ID))),
            uint256(1),
            "security slot 1: usedAnnouncementIds[id] must be true after announce"
        );

        // ---------- identifiers[identifierType] (slot 2, hashed by type) ----------
        // Both the seeded ISIN (DEFAULT_ISIN from _securityParams() bootstrap)
        // and the post-creation FIGI write are independently pinned to the
        // canonical string-field encoding at their derived slots.
        assertEq(
            vm.load(tokenAddr, MockB20AssetStorage.identifierSlot(IDENTIFIER_ISIN)),
            _expectedStringFieldSlot(DEFAULT_ISIN),
            "security slot 2: identifiers[ISIN] must hold the bootstrap-seeded short-string encoding"
        );
        assertEq(
            vm.load(tokenAddr, MockB20AssetStorage.identifierSlot(IDENTIFIER_FIGI)),
            _expectedStringFieldSlot(FIGI_VALUE),
            "security slot 2: identifiers[FIGI] must hold the post-creation short-string encoding"
        );

        // ============================================================
        //                  base.b20.redeem namespace
        // ============================================================

        // ---------- minimumRedeemable (slot 0) ----------
        assertEq(
            uint256(vm.load(tokenAddr, MockB20RedeemStorage.minimumRedeemableSlot())),
            MINIMUM_REDEEMABLE_MARKER,
            "redeem slot 0: minimumRedeemable must hold the post-mutation value"
        );

        // ---------- redeemPolicyIds (slot 1, packed) ----------
        // Layout:
        //   bits   0.. 63 : REDEEM_SENDER_POLICY lane
        //   bits  64..127 : reserved
        //   bits 128..191 : reserved
        //   bits 192..255 : reserved
        // The factory seeds lane 0 with ALWAYS_BLOCK_ID at creation; the
        // populate step overrides it with REDEEM_SENDER_MARKER via the public
        // `updatePolicy` surface. The reserved lanes MUST remain zero so the
        // Rust impl can't sneak fields into reserved space without us
        // noticing.
        uint256 packedRedeem = uint256(vm.load(tokenAddr, MockB20RedeemStorage.redeemPolicyIdsSlot()));
        assertEq(
            packedRedeem & 0xFFFFFFFFFFFFFFFF,
            uint256(redeemSenderMarker),
            "redeem slot 1 bits 0..63: REDEEM_SENDER_POLICY lane must hold the marker"
        );
        assertEq(packedRedeem >> 64, uint256(0), "redeem slot 1 bits 64..255: three reserved lanes must be zero");
    }

    /// @notice Verifies the factory-seeded default in `redeemPolicyIds`
    ///         lane 0 is `ALWAYS_BLOCK_ID` BEFORE any post-creation write.
    /// @dev    Companion to the populated-snapshot test. Catches a Rust
    ///         impl that skips the seed write at creation time — without
    ///         this, the populated-snapshot test would mask that bug
    ///         (the populate's `_setRedeemPolicy` would overwrite whatever
    ///         the seed left behind).
    function test_b20SecurityLayout_success_freshTokenSeedsRedeemPolicyToBlock() public view {
        uint256 packedRedeem = uint256(vm.load(address(token), MockB20RedeemStorage.redeemPolicyIdsSlot()));
        assertEq(
            packedRedeem & 0xFFFFFFFFFFFFFFFF,
            uint256(PolicyRegistryConstants.ALWAYS_BLOCK_ID),
            "fresh token: redeem slot 1 bits 0..63 must be ALWAYS_BLOCK_ID from factory seed"
        );
        assertEq(packedRedeem >> 64, uint256(0), "fresh token: redeem slot 1 bits 64..255 reserved lanes must be zero");
    }

    /// @notice Verifies the `base.b20.asset` and `base.b20.redeem`
    ///         namespaces derive from disjoint ERC-7201 roots.
    /// @dev    Two adjacent variant namespaces must not alias each other
    ///         or the base `base.b20` namespace. The disjoint-roots
    ///         property is tested for `base.b20` vs `base.b20.asset`
    ///         in `MockPolicyRegistryStorage.t.sol`-style tests already;
    ///         this pins the redeem-vs-security pair specifically.
    function test_b20SecurityLayout_success_namespaceRootsDisjoint() public pure {
        assertTrue(
            MockB20AssetStorage.STORAGE_LOCATION != MockB20RedeemStorage.STORAGE_LOCATION,
            "base.b20.asset and base.b20.redeem must derive to disjoint roots"
        );
    }

    /// @notice Populates the asset variant with non-default values
    ///         across every field of both added namespaces. Centralized so
    ///         the layout test reads as a single assertion sweep with no
    ///         interleaved mutations.
    function _populate() internal {
        // ---------- base.b20.asset ----------
        // sharesToTokensRatio: write the non-WAD marker via the public surface.
        _updateShareRatio(SHARE_RATIO_MARKER);
        // identifiers[FIGI]: post-creation operator write. ISIN was seeded
        // at creation (DEFAULT_ISIN via _securityParams() bootstrap).
        _grantOperator();
        vm.prank(operator);
        security().updateExtraMetadata(IDENTIFIER_FIGI, FIGI_VALUE);
        // usedAnnouncementIds[ANNOUNCEMENT_ID]: flip via announce.
        _announce(ANNOUNCEMENT_ID);

        // ---------- base.b20.redeem ----------
        // minimumRedeemable: post-creation admin write.
        _updateMinimumRedeemable(MINIMUM_REDEEMABLE_MARKER);
        // redeemPolicyIds lane 0: create a real custom policy in the
        // registry, then overwrite the factory-seeded ALWAYS_BLOCK_ID
        // default with that ID. The `updatePolicy` write path validates
        // the new ID via `policyExists`, so we can't use a synthetic
        // uint64 marker. Using a fresh real policy (distinct from the
        // ALWAYS_BLOCK_ID default) gives us a recognizable post-write
        // observable.
        redeemSenderMarker = StdPrecompiles.POLICY_REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        _setRedeemPolicy(redeemSenderMarker);
    }
}
