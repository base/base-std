// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {MockB20} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20AssetStorage, MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @title MockB20Asset
/// @author Coinbase
/// @notice Reference implementation of the `IB20Asset` variant.
///         Extends `MockB20` with the announcement bracket,
///         multiplier-based scaling, batched issuance, and
///         extra-metadata surfaces; all base behavior is
///         inherited unchanged.
///
/// @dev    Variant-specific state lives in `MockB20AssetStorage`'s
///         own ERC-7201 namespace (`base.b20.asset`), disjoint from
///         the base `MockB20Storage` namespace (`base.b20`), so the
///         variant composes additively without touching the base's
///         slot layout. The Rust precompile mirrors both namespaces
///         the same way.
///
///         **Announcement bracketing.** `announce(...)` is the
///         canonical disclosure-and-execute primitive: it emits
///         `Announcement(...)`, runs the operator's `internalCalls`
///         in-order via self-`delegatecall` (so `msg.sender` stays
///         the operator and the inner functions' role checks pass
///         normally), and emits `EndAnnouncement(id)`. Any inner
///         revert unwinds the entire transaction, so an
///         `Announcement` log is never observable without its
///         matching `EndAnnouncement`. `_checkSelector` rejects
///         recursive `announce` invocations (`AnnouncementInProgress`)
///         to keep the bracket exactly one level deep. The Rust impl
///         needs to mirror EVM `delegatecall` semantics exactly
///         (caller and storage preserved); a plain `call` to self
///         would change `msg.sender` to the contract address and
///         break the inner role checks.
///
///         **Multiplier default.** A stored `multiplier` of zero is
///         interpreted by the read surface as `WAD_PRECISION`, so a
///         freshly-etched token reports a 1:1 multiplier without
///         requiring the factory to write the default. The Rust impl
///         applies the same fallback so on-chain reads agree.
///
///         **Factory bootstrap.** Operator and admin gates honor
///         `_isPrivileged()` so the factory can stage initial
///         announcements, batched issuance, multipliers, and extra-metadata
///         entries during the bootstrap window without first granting
///         itself roles. Token invariants (supply-cap math, balance
///         accounting) are NOT bypassed anywhere.
contract MockB20Asset is MockB20, IB20Asset {
    // ============================================================
    //                          CONSTANTS
    // ============================================================

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Fixed-point precision for the multiplier. `1e18` (one
    ///         WAD) is the standard DeFi convention; `toScaledBalance`
    ///         and `scaledBalanceOf` divide by this after multiplying
    ///         by the stored multiplier, and `toRawBalance` multiplies
    ///         by this before dividing.
    uint256 public constant WAD_PRECISION = 1e18;

    // ============================================================
    //                           DECIMALS
    // ============================================================

    /// @notice Asset-variant decimals are chosen at creation from
    ///         `B20AssetCreateParams.decimals` (validated to
    ///         `[B20Constants.MIN_ASSET_DECIMALS, B20Constants.MAX_ASSET_DECIMALS]`
    ///         by the factory) and stored at
    ///         `MockB20AssetStorage.decimalsSlot()`. Overrides the
    ///         base `MockB20.decimals()` (which returns 18 for the
    ///         default variant) per the `IB20Asset` convention.
    function decimals() external view override(MockB20, IB20) returns (uint8) {
        return MockB20AssetStorage.layout().decimals;
    }

    // ============================================================
    //                        ANNOUNCEMENTS
    // ============================================================

    function announce(
        bytes[] calldata internalCalls,
        string calldata id,
        string calldata description,
        string calldata uri
    ) external onlyRole(OPERATOR_ROLE) {
        MockB20AssetStorage.Layout storage $ = MockB20AssetStorage.layout();
        if ($.usedAnnouncementIds[id]) revert AnnouncementIdAlreadyUsed(id);
        // Mark consumed BEFORE the emit and BEFORE any inner calls so
        // a delegatecall back into `announce` (defended-against by
        // `_checkSelector`) would fail this guard even if the
        // selector check were ever weakened.
        $.usedAnnouncementIds[id] = true;

        emit Announcement(msg.sender, id, description, uri);

        for (uint256 i = 0; i < internalCalls.length; i++) {
            _checkSelector(internalCalls[i]);
            (bool success,) = address(this).delegatecall(internalCalls[i]);
            if (!success) revert InternalCallFailed(internalCalls[i]);
        }

        emit EndAnnouncement(id);
    }

    function isAnnouncementIdUsed(string calldata id) external view returns (bool) {
        return MockB20AssetStorage.layout().usedAnnouncementIds[id];
    }

    // ============================================================
    //                          MULTIPLIER
    // ============================================================

    function multiplier() external view returns (uint256) {
        return _multiplier();
    }

    function toScaledBalance(uint256 rawBalance) external view returns (uint256) {
        return (rawBalance * _multiplier()) / WAD_PRECISION;
    }

    function toRawBalance(uint256 scaledBalance) external view returns (uint256) {
        return (scaledBalance * WAD_PRECISION) / _multiplier();
    }

    function scaledBalanceOf(address account) external view returns (uint256) {
        return (MockB20Storage.layout().balances[account] * _multiplier()) / WAD_PRECISION;
    }

    function updateMultiplier(uint256 newMultiplier) external onlyRole(OPERATOR_ROLE) {
        if (newMultiplier == 0) revert InvalidMultiplier();
        MockB20AssetStorage.layout().multiplier = newMultiplier;
        emit MultiplierUpdated(newMultiplier);
    }

    // ============================================================
    //                       BATCHED ISSUANCE
    // ============================================================

    /// @dev Pause + role enforced ONCE for the entire batch via the
    ///      entrypoint modifiers. Per-element zero-receiver guard is
    ///      inlined in the loop since `_mint` no longer carries an
    ///      input check.
    function batchMint(address[] calldata recipients, uint256[] calldata amounts)
        external
        whenNotPaused(PausableFeature.MINT)
        onlyRole(MINT_ROLE)
    {
        if (recipients.length != amounts.length) revert LengthMismatch(recipients.length, amounts.length);
        if (recipients.length == 0) revert EmptyBatch();
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidReceiver(recipients[i]);
            _mint(recipients[i], amounts[i]);
        }
    }

    // ============================================================
    //                       EXTRA METADATA
    // ============================================================

    function extraMetadata(string calldata key) external view returns (string memory) {
        return MockB20AssetStorage.layout().extraMetadata[key];
    }

    function updateExtraMetadata(string calldata key, string calldata value) external onlyRole(METADATA_ROLE) {
        if (bytes(key).length == 0) revert InvalidMetadataKey();
        MockB20AssetStorage.layout().extraMetadata[key] = value;
        emit ExtraMetadataUpdated(key, value);
    }

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    /// @dev Stored `0` resolves to `WAD_PRECISION` so a freshly-etched
    ///      token (no factory write yet) reports a 1:1 multiplier.
    function _multiplier() internal view returns (uint256) {
        uint256 stored = MockB20AssetStorage.layout().multiplier;
        return stored == 0 ? WAD_PRECISION : stored;
    }

    /// @dev Validates a single `internalCalls[i]` blob before
    ///      `announce` issues the inner `delegatecall`. Two checks:
    ///      (1) the blob carries at least four bytes (a function
    ///      selector), else `InternalCallMalformed` — a too-short
    ///      payload would otherwise hit the contract's fallback
    ///      surface, which is not what an "internal call" is supposed
    ///      to mean; (2) the selector is not `announce` itself, else
    ///      `AnnouncementInProgress` — keeps the bracket one level
    ///      deep so indexers can rely on `Announcement` /
    ///      `EndAnnouncement` pairing without nesting.
    ///
    ///      The check is a denylist (only `announce` is blocked), not
    ///      an allowlist of approved corp-action functions: the
    ///      operator already needs both `OPERATOR_ROLE` to
    ///      call `announce` AND whatever role each inner function
    ///      requires (e.g. `MINT_ROLE` for `batchMint`), so the
    ///      authorization story is already enforced by the inner
    ///      functions' own gates. The recursion guard exists to
    ///      protect the EVENT topology (no nested brackets), not the
    ///      authorization topology.
    function _checkSelector(bytes calldata call) internal pure {
        if (call.length < 4) revert InternalCallMalformed(call);
        bytes4 sel = bytes4(call[:4]);
        if (sel == IB20Asset.announce.selector) revert AnnouncementInProgress();
    }
}
