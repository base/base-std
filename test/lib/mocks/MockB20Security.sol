// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {MockB20} from "test/lib/mocks/MockB20.sol";
import {MockB20SecurityStorage, MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

/// @title MockB20Security
/// @author Coinbase
/// @notice Reference implementation of the `IB20Security` variant.
///         Extends `MockB20` with the announcement bracket,
///         share-ratio accounting, batched issuance, and
///         security-identifier surfaces; all base behavior is
///         inherited unchanged.
///
/// @dev    Variant-specific state lives in `MockB20SecurityStorage`'s
///         own ERC-7201 namespace (`base.b20.security`), disjoint from
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
///         **Share ratio default.** A stored `sharesToTokensRatio` of
///         zero is interpreted by the read surface as `WAD_PRECISION`,
///         so a freshly-etched token reports a 1:1 ratio without
///         requiring the factory to write the default. The Rust impl
///         applies the same fallback so on-chain reads agree.
///
///         **Factory bootstrap.** Operator and admin gates honor
///         `_isPrivileged()` so the factory can stage initial
///         announcements, batched issuance, ratios, and identifiers
///         during the bootstrap window without first granting itself
///         roles. Token invariants (supply-cap math, balance
///         accounting) are NOT bypassed anywhere.
contract MockB20Security is MockB20, IB20Security {
    // ============================================================
    //                          CONSTANTS
    // ============================================================

    bytes32 public constant SECURITY_OPERATOR_ROLE = keccak256("SECURITY_OPERATOR_ROLE");

    /// @notice Fixed-point precision for the share ratio. `1e18` (one
    ///         WAD) is the standard DeFi convention; `toShares` and
    ///         `sharesOf` divide by this after multiplying by the
    ///         stored ratio.
    uint256 public constant WAD_PRECISION = 1e18;

    // ============================================================
    //                           DECIMALS
    // ============================================================

    /// @notice Security-variant decimals are fixed at 6. Overrides the
    ///         base `MockB20.decimals()` (which returns 18 for the
    ///         default variant) per the `IB20Security` convention.
    function decimals() external pure override(MockB20, IB20) returns (uint8) {
        return 6;
    }

    // ============================================================
    //                        ANNOUNCEMENTS
    // ============================================================

    function announce(
        bytes[] calldata internalCalls,
        string calldata id,
        string calldata description,
        string calldata uri
    ) external onlyRole(SECURITY_OPERATOR_ROLE) {
        MockB20SecurityStorage.Layout storage $ = MockB20SecurityStorage.layout();
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
        return MockB20SecurityStorage.layout().usedAnnouncementIds[id];
    }

    // ============================================================
    //                         SHARE RATIO
    // ============================================================

    function sharesToTokensRatio() external view returns (uint256) {
        return _sharesToTokensRatio();
    }

    function toShares(uint256 balance) external view returns (uint256) {
        return (balance * _sharesToTokensRatio()) / WAD_PRECISION;
    }

    function sharesOf(address account) external view returns (uint256) {
        return (MockB20Storage.layout().balances[account] * _sharesToTokensRatio()) / WAD_PRECISION;
    }

    function updateShareRatio(uint256 newSharesToTokensRatio) external onlyRole(SECURITY_OPERATOR_ROLE) {
        MockB20SecurityStorage.layout().sharesToTokensRatio = newSharesToTokensRatio;
        emit ShareRatioUpdated(newSharesToTokensRatio);
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
    //                     SECURITY IDENTIFIERS
    // ============================================================

    function securityIdentifier(string calldata identifierType) external view returns (string memory) {
        return MockB20SecurityStorage.layout().identifiers[identifierType];
    }

    function updateSecurityIdentifier(string calldata identifierType, string calldata value)
        external
        onlyRole(SECURITY_OPERATOR_ROLE)
    {
        if (bytes(identifierType).length == 0) revert InvalidIdentifierType();
        MockB20SecurityStorage.layout().identifiers[identifierType] = value;
        emit SecurityIdentifierUpdated(identifierType, value);
    }

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    /// @dev Stored `0` resolves to `WAD_PRECISION` so a freshly-etched
    ///      token (no factory write yet) reports a 1:1 ratio.
    function _sharesToTokensRatio() internal view returns (uint256) {
        uint256 stored = MockB20SecurityStorage.layout().sharesToTokensRatio;
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
    ///      operator already needs both `SECURITY_OPERATOR_ROLE` to
    ///      call `announce` AND whatever role each inner function
    ///      requires (e.g. `MINT_ROLE` for `batchMint`), so the
    ///      authorization story is already enforced by the inner
    ///      functions' own gates. The recursion guard exists to
    ///      protect the EVENT topology (no nested brackets), not the
    ///      authorization topology.
    function _checkSelector(bytes calldata call) internal pure {
        if (call.length < 4) revert InternalCallMalformed(call);
        bytes4 sel = bytes4(call[:4]);
        if (sel == IB20Security.announce.selector) revert AnnouncementInProgress();
    }
}
