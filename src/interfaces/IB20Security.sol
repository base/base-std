// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IDefaultToken} from "./IDefaultToken.sol";

/// @title ISecurityToken
/// @notice A B-20 token variant for tokenized securities (equities, ETFs,
///         commodities, etc.). Extends `IDefaultToken` with primitives
///         specific to securities: holder-impacting announcements,
///         split-safe share-ratio accounting, security-identifier
///         metadata, and admin batch mint / burn for unusual corporate actions.
///
/// @dev    **Inherited surface.** `IDefaultToken` already provides the
///         pieces that are shared with stablecoins and other variants:
///         ERC-20 surface, mint / burn (gated by `MINT_ROLE` / `BURN_ROLE`),
///         pause vectors (including REDEEM), permit, contract URI,
///         supply cap, and OZ-style role management. Security tokens use
///         all of these as-is and do not redeclare them here.
///
///         **Security-specific additions.** This interface adds:
///         1. `announcement(...)` plus an `ANNOUNCE_ROLE` for posting
///            holder-impacting disclosures (corporate actions, name
///            changes, splits, etc.).
///         3. `shareRatio` + `toShares` + `sharesOf` for split-safe
///            DeFi-compatible share accounting.
///         4. `create(...)` plus `ISSUER_ROLE` and a per-caller rate
///            limit for the compliant primary-market issuance path.
///            Distinct from the inherited `mint` because securities
///            have legal definitions around what constitutes "creation".
///         5. `adminMint(...)` / `adminBurn(...)` cold-path batch
///            operations for unusual corporate actions.
///         6. `updateName(...)` / `updateSymbol(...)` security-specific
///            paths that take an announcement ID. These are the
///            canonical name/symbol update functions for security
///            tokens; the inherited `setName` / `setSymbol` from
///            `IDefaultToken` are present in the interface but
///            implementations typically revert them on security tokens
///            so that name/symbol changes always carry an announcement.
///         7. `securityIdentifier` / `updateSecurityIdentifier` for
///            ISIN, CUSIP, FIGI, and similar off-chain registry IDs.
///
///         **Operationally typical configuration.** Security-token
///         issuers usually do NOT grant `MINT_ROLE` (the inherited mint
///         path is disabled in favor of `create` and `adminMint`) and
///         do NOT grant `BURN_ROLE` (holders use `redeem` for off-chain
///         settlement; admins use `adminBurn` for cold-path destruction).
///         Capability bits relevant to securities live in the
///         `Capabilities` library bits 16..23 (e.g. `SECURITY_CREATABLE`,
///         `SHARE_RATIO_MUTABLE`).
interface ISecurityToken is IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice An announcement ID was reused. Each ID may be consumed
    ///         exactly once across the lifetime of the token.
    error AnnouncementIdAlreadyUsed(string id);


    /// @notice `updateSecurityIdentifier` was called with an empty
    ///         `identifierType` string.
    error InvalidIdentifierType();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SharesRedeemed(address from, uint256 amt, uint128 ratioTokensToShares);

    event MinimumRedeemableUpdated(uint248 newMinimumRedeemable);

    event ShareRatioUpdated(uint128 ratioTokensToShares);

    event IdentifierUpdated(string identifierType, string value);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `annoucement`, `updateShareRatio`, 
    /// `updateSecurityIdentifier`, `updateName`, `updateSymbol`, .
    function SECURITY_OPERATOR_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement. The `id` is consumed:
    ///         subsequent calls in the same transaction that reference
    ///         this `id` are gated on it having been announced first;
    ///         subsequent calls in later transactions may not reuse it.
    /// @dev    Requires `SECURITY_OPERATOR_ROLE`. Reverts with
    ///         `AnnouncementIdAlreadyUsed` on `id` reuse.
    function announce(string calldata id, string calldata description, string calldata uri) external;

    /// @notice Whether a given announcement ID has been consumed.
    function isAnnouncementIdUsed(string calldata id) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              SHARE RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice The current token-to-share ratio.
    function shareRatio() external view returns (uint128 sharesToTokensRatio);

    /// @notice Converts a raw token balance to its current share count via the active share ratio.
    function toShares(uint256 balance) external view returns (uint256);

    /// @notice Convenience: `toShares(balanceOf(account))`.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Sets a new share ratio (typically following an off-chain
    ///         stock split or reverse split). Holder balances are NOT
    ///         rewritten; the displayed share count derives from the
    ///         new ratio at read time, preserving DeFi composability.
    /// @dev    Requires `SECURITY_OPERATOR_ROLE` and an
    ///         `Announcement(id, ...)` emitted earlier in the same
    ///         transaction with the same id.
    function updateShareRatio(uint128 newSharesToTokensRatio) external;

    /*//////////////////////////////////////////////////////////////
                       ISSUANCE: cold-path batch
    //////////////////////////////////////////////////////////////*/

    function mint(
        string calldata id,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    function burn(
        string calldata announcementId,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;

    /*//////////////////////////////////////////////////////////////
                            REDEMPTION
    //////////////////////////////////////////////////////////////*/

    function redeem(uint256 amount) external;
    
    function redeemWithMemo(uint256 amount, string calldata memo) external;

    function updateMinimumRedeemable(uint256 newMinimumRedeemable) external;

    function minimumRedeemable() external view returns (uint256);


    /*//////////////////////////////////////////////////////////////
                       SECURITY IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the value of the named identifier (e.g. ISIN,
    ///         CUSIP, FIGI). Returns the empty string if not set.
    function securityIdentifier(string calldata identifierType) external view returns (string memory);

    /// @notice Sets, updates, or removes a security identifier. If
    ///         `remove` is true, the entry is deleted (`value` is
    ///         ignored).
    /// @dev    Requires `SECURITY_OPERATOR_ROLE` and an
    ///         `Announcement(id, ...)` emitted earlier in the same
    function updateSecurityIdentifier(
        string calldata identifierType,
        string calldata value
    ) external;

