// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";
import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {MockB20} from "test/lib/mocks/MockB20.sol";
import {MockB20SecurityStorage, MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";
import {MockB20RedeemStorage} from "test/lib/mocks/MockB20Storage.sol";

/// @title MockB20Security
/// @author Coinbase
/// @notice Reference implementation of the `IB20Security` variant.
///         Extends `MockB20` with the announcement bracket,
///         share-ratio accounting, batched issuance / clawback,
///         redemption, and security-identifier surfaces; all base
///         behavior is inherited unchanged.
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
///         **Policy override.** `REDEEM_SENDER_POLICY` lives in this
///         variant's own `redeemPolicyIds` packed slot, mirroring the
///         per-operation packed-slot layout the base uses for
///         `transferPolicyIds` / `mintPolicyIds`. `_readPolicyId` and
///         `_writePolicyId` are overridden to handle that slot first
///         and fall through to `super` for everything else, which is
///         the pattern `MockB20Storage`'s natspec explicitly
///         anticipates.
///
///         **Share ratio default.** A stored `sharesToTokensRatio` of
///         zero is interpreted by the read surface as `WAD_PRECISION`,
///         so a freshly-etched token reports a 1:1 ratio without
///         requiring the factory to write the default. The Rust impl
///         applies the same fallback so on-chain reads agree.
///
///         **Factory bootstrap.** Operator and admin gates honor
///         `_isPrivileged()` so the factory can stage initial
///         announcements, batched issuance, ratios, identifiers, and
///         minimum-redeemable values during the bootstrap window
///         without first granting itself roles. The two paths that
///         the factory will never legitimately call during bootstrap
///         (`redeem` / `redeemWithMemo`, which are holder-initiated,
///         and `batchBurn`, which is a corporate-actions clawback
///         against existing balances) deliberately do NOT bypass
///         their authorization checks: there is no init-time use case
///         for them, so the bypass would be dead code that widens the
///         attack surface without buying anything. Token invariants
///         (supply-cap math, balance accounting, share-amount floor
///         on `redeem`) are NOT bypassed anywhere.
contract MockB20Security is MockB20, IB20Security {
    // ============================================================
    //                          CONSTANTS
    // ============================================================

    bytes32 public constant SECURITY_OPERATOR_ROLE = keccak256("SECURITY_OPERATOR_ROLE");
    bytes32 public constant BURN_FROM_ROLE = keccak256("BURN_FROM_ROLE");

    bytes32 public constant REDEEM_SENDER_POLICY = keccak256("REDEEM_SENDER_POLICY");

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
    //                          MODIFIERS
    // ============================================================

    /// @dev Like the base `onlyRole` but without the factory bootstrap
    ///      bypass: the role check is unconditional, even for the
    ///      factory in the init window. Reserved for variant paths
    ///      that deliberately reject the bypass — currently just
    ///      `batchBurn`, the corporate-actions clawback that has no
    ///      init-time use case (see this contract's natspec). Lives
    ///      here, not on the base, because no base function needs the
    ///      stricter gate.
    modifier onlyRoleStrict(bytes32 role) {
        if (!hasRole(role, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
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
    //                  BATCHED ISSUANCE / CLAWBACK
    // ============================================================

    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external {
        if (recipients.length != amounts.length) revert LengthMismatch(recipients.length, amounts.length);
        if (recipients.length == 0) revert EmptyBatch();
        // Per-element call into _mint: role / pause checks repeat (idempotent),
        // but MINT_RECEIVER_POLICY policy and supply-cap accumulation are correctly
        // applied per recipient. Cleaner than re-deriving the per-element body.
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /// @dev `onlyRoleStrict` (not `onlyRole`): the factory bootstrap
    ///      bypass is deliberately NOT honored here, per the contract
    ///      natspec — clawback against existing balances has no init-time
    ///      use case, so granting the factory a bypass would only widen
    ///      the attack surface.
    function batchBurn(address[] calldata accounts, uint256[] calldata amounts)
        external
        onlyRoleStrict(BURN_FROM_ROLE)
    {
        if (accounts.length != amounts.length) {
            revert LengthMismatch(accounts.length, amounts.length);
        }
        if (accounts.length == 0) revert EmptyBatch();
        if (_isPaused(PausableFeature.BURN)) revert ContractPaused(PausableFeature.BURN);
        for (uint256 i = 0; i < accounts.length; i++) {
            // Per-element zero-amount guard, matching the Rust precompile. Fires inside
            // the loop before the balance check, so a zero in any slot reverts the whole
            // batch (all-or-nothing atomicity).
            if (amounts[i] == 0) revert InvalidAmount();
            _burnRaw(accounts[i], amounts[i]);
        }
    }

    // ============================================================
    //                          REDEMPTION
    // ============================================================

    function redeem(uint256 amount) external {
        uint256 ratio = _redeemBurn(amount);
        emit Redeemed(msg.sender, amount, ratio);
    }

    function redeemWithMemo(uint256 amount, bytes32 memo) external {
        uint256 ratio = _redeemBurn(amount);
        // Order matters: Transfer (in _redeemBurn), then Memo, then Redeemed.
        emit Memo(msg.sender, memo);
        emit Redeemed(msg.sender, amount, ratio);
    }

    function updateMinimumRedeemable(uint256 newMinimumRedeemable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MockB20RedeemStorage.layout().minimumRedeemable = newMinimumRedeemable;
        emit MinimumRedeemableUpdated(msg.sender, newMinimumRedeemable);
    }

    function minimumRedeemable() external view returns (uint256) {
        return MockB20RedeemStorage.layout().minimumRedeemable;
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
    //                       POLICY OVERRIDES
    // ============================================================

    /// @dev Variant-first policy resolution: REDEEM_SENDER_POLICY lives in
    ///      this variant's own packed slot; everything else falls
    ///      through to the base. The base's UnsupportedPolicyType
    ///      revert is the terminal case.
    function _readPolicyId(bytes32 policyScope) internal view virtual override returns (uint64) {
        if (policyScope == REDEEM_SENDER_POLICY) {
            return MockB20RedeemStorage.layout().redeemPolicyIds.sender;
        }
        return super._readPolicyId(policyScope);
    }

    function _writePolicyId(bytes32 policyScope, uint64 newPolicyId) internal virtual override {
        if (policyScope == REDEEM_SENDER_POLICY) {
            MockB20RedeemStorage.layout().redeemPolicyIds.sender = newPolicyId;
            return;
        }
        super._writePolicyId(policyScope, newPolicyId);
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

    /// @dev Burn the caller's balance for redemption. Returns the
    ///      ratio used for the share-amount math so callers can emit
    ///      `Redeemed` with the same value the floor was checked
    ///      against. No factory bypass: redeem is a holder-initiated
    ///      path that the factory has no legitimate reason to invoke
    ///      during bootstrap, so the bypass is omitted by design.
    function _redeemBurn(uint256 amount) internal returns (uint256 ratio) {
        if (_isPaused(PausableFeature.REDEEM)) revert ContractPaused(PausableFeature.REDEEM);
        MockB20RedeemStorage.Layout storage $ = MockB20RedeemStorage.layout();
        uint64 REDEEMSenderPolicyId = $.redeemPolicyIds.sender;
        if (!IPolicyRegistry(POLICY_REGISTRY).isAuthorized(REDEEMSenderPolicyId, msg.sender)) {
            revert PolicyForbids(REDEEM_SENDER_POLICY, REDEEMSenderPolicyId);
        }
        ratio = _sharesToTokensRatio();
        uint256 shares = (amount * ratio) / WAD_PRECISION;
        uint256 minimum = $.minimumRedeemable;
        // Always reject zero-share redemptions, even if the configured
        // minimum is 0 — burning token dust that resolves to no shares
        // is never the holder's intent.
        if (shares == 0 || shares < minimum) revert BelowMinimumRedeemable(shares, minimum);
        _burnRaw(msg.sender, amount);
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
