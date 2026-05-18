// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IDefaultToken} from "./IDefaultToken.sol";

/// @title IAssetToken
/// @notice A B-20 token variant for tokenized assets (equities, ETFs,
///         commodities, etc.). Extends `IDefaultToken` with primitives
///         specific to assets: holder-impacting announcements,
///         split-safe share-ratio accounting, security-identifier
///         metadata, compliant issuance via `create`, and cold-path
///         admin batch mint / burn for unusual corporate actions.
///
/// @dev    **Inherited surface.** `IDefaultToken` already provides the
///         pieces that are shared with stablecoins and other variants:
///         ERC-20 surface, mint / burn (gated by `MINT_ROLE` / `BURN_ROLE`),
///         redeem / redeemWithMemo / minimumRedeemable / setMinimumRedeemable
///         (gated by the redeemer slot of the compound transfer policy),
///         pause vectors (including REDEEM at bit 3), permit, contract URI,
///         supply cap, and OZ-style role management. Security tokens use
///         all of these as-is and do not redeclare them here.
///
///         **Security-specific additions.** This interface adds:
///         1. `announcement(...)` plus an `ANNOUNCE_ROLE` for posting
///            holder-impacting disclosures (corporate actions, name
///            changes, splits, etc.).
///         2. **Announcement coupling**: every security-specific
///            metadata-changing operation (`updateShareRatio`,
///            `updateExtraMetadata`, `updateName`, `updateSymbol`,
///            `adminMint`, `adminBurn`) MUST reference an announcement
///            ID emitted via `announcement(...)` earlier in the same
///            transaction. Implementations enforce this via transient
///            storage so the chain itself, not the issuer's policy,
///            guarantees the audit-trail invariant.
///         3. `shareRatio` + `toShares` + `sharesOf` for split-safe
///            DeFi-compatible share accounting.
///         4. `create(...)` plus `ISSUER_ROLE` and a per-caller rate
///            limit for the compliant primary-market issuance path.
///            Distinct from the inherited `mint` because assets
///            have legal definitions around what constitutes "creation".
///         5. `adminMint(...)` / `adminBurn(...)` cold-path batch
///            operations for unusual corporate actions.
///         6. `updateName(...)` / `updateSymbol(...)` security-specific
///            paths that take an announcement ID. These are the
///            canonical name/symbol update functions for security
///            tokens; the inherited `setName` / `setSymbol` from
///            `IDefaultToken` are present in the interface but
///            implementations typically revert them on asset tokens
///            so that name/symbol changes always carry an announcement.
///         7. `securityIdentifier` / `updateExtraMetadata` for
///            ISIN, CUSIP, FIGI, and similar off-chain registry IDs.
///
///         **Operationally typical configuration.** Security-token
///         issuers usually do NOT grant `MINT_ROLE` (the inherited mint
///         path is disabled in favor of `create` and `adminMint`) and
///         do NOT grant `BURN_ROLE` (holders use `redeem` for off-chain
///         settlement; admins use `adminBurn` for cold-path destruction).
///         Capability bits relevant to assets live in the
///         `Capabilities` library bits 16..23 (e.g. `ASSET_CREATABLE`,
///         `SHARE_RATIO_MUTABLE`).
interface IAssetToken is IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice A security-specific operation was called without a
    ///         matching prior `announcement(id, ...)` in the same
    ///         transaction.
    error AnnouncementRequired(string id);

    /// @notice An announcement ID was reused. Each ID may be consumed
    ///         exactly once across the lifetime of the token.
    error AnnouncementIdAlreadyUsed(string id);

    /// @notice `updateShareRatio` was called with a zero numerator or
    ///         denominator.
    error InvalidShareRatio();

    /// @notice `create` was called by a caller whose remaining create
    ///         allowance under the configured rate limit is less than
    ///         the requested amount.
    error CreateRateLimitExceeded(address caller);

    /// @notice `updateExtraMetadata` was called with an empty
    ///         `identifierType` string.
    error InvalidIdentifierType();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A holder-impacting announcement. Posted before any
    ///         metadata-changing operation that references the same
    ///         `id`.
    event Announcement(address indexed caller, string id, string description, string uri);

    /// @notice The token-to-share ratio changed (typically a stock split
    ///         or reverse split). Indexers should refresh `sharesOf`
    ///         views for all holders on receipt.
    event ShareRatioUpdated(
        address indexed caller,
        string announcementId,
        uint48 oldNumerator,
        uint48 oldDenominator,
        uint48 newNumerator,
        uint48 newDenominator
    );

    /// @notice A extra metadata (ISIN, CUSIP, FIGI, etc.) was set,
    ///         changed, or removed. `value` is the empty string on
    ///         removal.
    event ExtraMetadataUpdated(
        address indexed caller, string announcementId, string identifierType, string value
    );

    /// @notice Supply created via the compliant issuance path.
    event Created(address indexed to, uint256 amount);

    /// @notice Supply created via the cold-path admin batch.
    event AdminMinted(address indexed caller, string announcementId, uint256 totalAmount);

    /// @notice Supply destroyed via the cold-path admin batch.
    event AdminBurned(address indexed caller, string announcementId, uint256 totalAmount);

    /// @notice Per-caller create rate-limit configuration changed.
    event CreateRateLimitConfigured(address indexed caller, uint256 maxAmount, uint256 interval);

    // NOTE on `NameUpdated` / `SymbolUpdated` / `Redeemed` /
    // `MinimumRedeemableUpdated`: all four are inherited from
    // `IDefaultToken` and are not redeclared here. Security
    // implementations of `updateName` / `updateSymbol` emit the
    // inherited `NameUpdated` / `SymbolUpdated` event after the matching
    // `Announcement(id, ...)` has been emitted earlier in the
    // transaction; indexers correlate the two via the shared
    // transaction hash.

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `announcement`. Held separately so a
    ///         24/7 disclosure team can post announcements without
    ///         holding supply-changing or admin authority.
    function ANNOUNCE_ROLE() external view returns (bytes32);

    /// @notice Required to call `create` (compliant primary-market
    ///         issuance), `adminMint` (cold-path batch issuance), and
    ///         `adminBurn` (cold-path batch destruction). Distinct from
    ///         the inherited `MINT_ROLE` so security-specific issuance
    ///         authority can be split from the generic mint surface
    ///         (which is typically not granted at all on security
    ///         tokens).
    function ISSUER_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement. The announcement
    ///         does not store its `description` or `uri` on-chain (per
    ///         current design, see DESIGN_NOTES); the data lives only
    ///         in the emitted event log. The `id` is consumed:
    ///         subsequent calls in the same transaction that reference
    ///         this `id` are gated on it having been announced first;
    ///         subsequent calls in later transactions may not reuse it.
    /// @dev    Requires `ANNOUNCE_ROLE`. Reverts with
    ///         `AnnouncementIdAlreadyUsed` on `id` reuse.
    function announcement(string calldata id, string calldata description, string calldata uri) external;

    /// @notice Whether the given announcement ID has been consumed.
    function isAnnouncementIdUsed(string calldata id) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              SHARE RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice The current token-to-share ratio. A 1:1 ratio (numerator
    ///         == denominator) means raw token balances equal share
    ///         counts. A 2:1 ratio (e.g. after a 2-for-1 split) means
    ///         each raw token represents 2 shares.
    function shareRatio() external view returns (uint48 numerator, uint48 denominator);

    /// @notice Converts a raw token balance to its current share count
    ///         via the active share ratio. Equivalent to
    ///         `balance * denominator / numerator`.
    function toShares(uint256 balance) external view returns (uint256);

    /// @notice Convenience: `toShares(balanceOf(account))`.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Sets a new share ratio (typically following an off-chain
    ///         stock split or reverse split). Holder balances are NOT
    ///         rewritten; the displayed share count derives from the
    ///         new ratio at read time, preserving DeFi composability.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an
    ///         `Announcement(id, ...)` emitted earlier in the same
    ///         transaction with the same id. Both numerator and
    ///         denominator must be non-zero.
    function updateShareRatio(string calldata announcementId, uint48 newNumerator, uint48 newDenominator) external;

    /*//////////////////////////////////////////////////////////////
                          ISSUANCE: create
    //////////////////////////////////////////////////////////////*/

    /// @notice The compliant issuance path. Mints `amount` to `to`
    ///         subject to the standard transfer-policy mint-recipient
    ///         check AND to a per-caller rate limit configured by the
    ///         admin.
    /// @dev    Requires `ISSUER_ROLE`. Subject to the inherited supply
    ///         cap (`supplyCap`). Distinct from the inherited `mint`
    ///         semantically because assets have legal definitions
    ///         around what constitutes "creation"; this is the function
    ///         product surfaces should call. Tokens that want to disable
    ///         normal issuance after a bootstrap period can revoke
    ///         `ISSUER_ROLE` from all callers.
    function create(address to, uint256 amount) external;

    /// @notice The remaining create allowance for `caller` under their
    ///         current rate-limit configuration.
    function createAllowance(address caller) external view returns (uint256);

    /// @notice Configures the per-call create rate limit for `caller`:
    ///         `maxAmount` total over each `interval` (seconds).
    /// @dev    Requires `DEFAULT_ADMIN_ROLE`. Setting `maxAmount` to 0
    ///         or interval to 0 effectively disables that caller's
    ///         create.
    function configureCreateRateLimit(address caller, uint256 maxAmount, uint256 interval) external;

    /*//////////////////////////////////////////////////////////////
                       ISSUANCE: cold-path batch
    //////////////////////////////////////////////////////////////*/

    /// @notice Cold-path batch mint. Used for unusual or emergency
    ///         issuance (e.g. distribution of a stock dividend to many
    ///         holders). All recipients must satisfy
    ///         `isAuthorizedMintRecipient` on the active transfer
    ///         policy.
    /// @dev    Requires `ISSUER_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction with the same
    ///         `announcementId`. Subject to the inherited `supplyCap`.
    ///         Reverts atomically if any single recipient fails;
    ///         partial mints are not possible.
    function adminMint(
        string calldata announcementId,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    /// @notice Cold-path batch burn. Used for cold-path corporate
    ///         actions (reverse-tender settlement, mass-corrections
    ///         under regulatory direction, etc.). NOT subject to the
    ///         inherited pause vectors: admins can `adminBurn` even
    ///         while transfers and burns are paused.
    /// @dev    Requires `ISSUER_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction with the same
    ///         `announcementId`. Reverts atomically if any single
    ///         account lacks sufficient balance; partial burns are not
    ///         possible.
    function adminBurn(
        string calldata announcementId,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;

    /*//////////////////////////////////////////////////////////////
                       ASSET IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the value of the named identifier (e.g. ISIN,
    ///         CUSIP, FIGI). Returns the empty string if not set.
    function securityIdentifier(string calldata identifierType) external view returns (string memory);

    /// @notice Returns all currently-set identifiers as `[type, value]`
    ///         pairs. Order is not guaranteed; callers should treat the
    ///         array as a set. The expected count is small (a handful
    ///         per security), so enumeration is safe.
    function getExtraMetadatas() external view returns (string[2][] memory);

    /// @notice Sets, updates, or removes a extra metadata. If
    ///         `remove` is true, the entry is deleted (`value` is
    ///         ignored).
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an
    ///         `Announcement(id, ...)` emitted earlier in the same
    ///         transaction. Reverts with `InvalidIdentifierType` on
    ///         empty `identifierType`.
    function updateExtraMetadata(
        string calldata announcementId,
        string calldata identifierType,
        string calldata value,
        bool remove
    ) external;

    /*//////////////////////////////////////////////////////////////
                       NAME / SYMBOL UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the token's name (e.g. corporate rebrand).
    ///         Reads via the inherited `name()` accessor reflect the
    ///         new value immediately. Affects EIP-712 domain separator
    ///         computation (used by `permit`); callers signing permits
    ///         should re-read the relevant domain fields immediately
    ///         before signing. Emits the inherited `NameUpdated` event
    ///         from `IDefaultToken`.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an
    ///         `Announcement(id, ...)` emitted earlier in the same
    ///         transaction with the same id.
    ///
    ///         Note: `IDefaultToken.setName(newName)` is also in this
    ///         interface (inherited) but security-token implementations
    ///         typically revert it so that all name changes carry an
    ///         announcement. Use `updateName` here for the canonical
    ///         security path.
    function updateName(string calldata announcementId, string calldata newName) external;

    /// @notice Updates the token's symbol (e.g. ticker change). Reads
    ///         via the inherited `symbol()` accessor reflect the new
    ///         value immediately. Emits the inherited `SymbolUpdated`
    ///         event from `IDefaultToken`.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an
    ///         `Announcement(id, ...)` emitted earlier in the same
    ///         transaction with the same id.
    ///
    ///         Same caveat as `updateName`: the inherited
    ///         `setSymbol(newSymbol)` is typically reverted by security
    ///         implementations.
    function updateSymbol(string calldata announcementId, string calldata newSymbol) external;
}
