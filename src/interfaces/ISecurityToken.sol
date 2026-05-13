// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IDefaultToken} from "./IDefaultToken.sol";

/// @title ISecurityToken
/// @notice A B-20 token variant for tokenized securities (equities, ETFs,
///         commodities, etc.). Extends IDefaultToken with primitives specific
///         to securities: split-safe share accounting, holder announcements,
///         security-identifier metadata, compliant issuance via `create`, and
///         user-side `redeem` for off-chain settlement.
/// @dev    Security tokens enforce announcement coupling on every
///         metadata-changing operation: each call must reference an
///         announcement ID that was emitted via `announcement(...)` earlier
///         in the same transaction. Implementations enforce this via
///         transient storage so the chain itself, not the issuer's policy,
///         guarantees the audit trail invariant.
///
///         Security tokens typically configure their `capabilities()` with
///         `MINTABLE` unset, replacing the inherited `mint`/`mintWithMemo`
///         path with the security-specific `create` (rate-limited compliant
///         issuance) and `adminMint` (cold-path batch issuance) functions.
///         `BURNABLE` is similarly typically unset; holders burn via
///         `redeem` and admins burn via `adminBurn`. See `Capabilities` for
///         the bit definitions and the `BURN_BLOCKED` bit for sanctions
///         enforcement.
interface ISecurityToken is IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AnnouncementRequired(string id);
    error AnnouncementIdAlreadyUsed(string id);
    error InvalidShareRatio();
    error CreateRateLimitExceeded(address caller);
    error RedeemNotAuthorized(address caller);
    error RedeemBelowMinimum(uint256 amount, uint256 minimum);
    error InvalidIdentifierType();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A holder-impacting announcement. Posted before any
    ///         metadata-changing operation that references the same `id`.
    event Announcement(address indexed caller, string id, string description, string uri);

    /// @notice The token-to-share ratio changed (typically a stock split or
    ///         reverse split). Indexers should refresh `sharesOf` views for
    ///         all holders on receipt.
    event ShareRatioUpdated(
        address indexed caller,
        string announcementId,
        uint48 oldNumerator,
        uint48 oldDenominator,
        uint48 newNumerator,
        uint48 newDenominator
    );

    /// @notice The token's name changed (e.g. corporate rebrand: Facebook to
    ///         Meta). Wallets and explorers should refresh their cache.
    event NameUpdated(address indexed caller, string announcementId, string newName);

    /// @notice The token's symbol/ticker changed. Same indexer implications
    ///         as `NameUpdated`.
    event SymbolUpdated(address indexed caller, string announcementId, string newSymbol);

    /// @notice A security identifier (ISIN, CUSIP, FIGI, etc.) was set,
    ///         changed, or removed. `value` is the empty string on removal.
    event SecurityIdentifierUpdated(
        address indexed caller, string announcementId, string identifierType, string value
    );

    /// @notice Supply created via the compliant issuance path.
    event Created(address indexed to, uint256 amount);

    /// @notice Supply created via the cold-path admin batch.
    event AdminMinted(address indexed caller, string announcementId, uint256 totalAmount);

    /// @notice Supply destroyed via the cold-path admin batch.
    event AdminBurned(address indexed caller, string announcementId, uint256 totalAmount);

    /// @notice User-initiated burn for off-chain redemption.
    event Redeemed(address indexed from, uint256 amount);

    event MinimumRedeemableUpdated(uint256 newMinimum);
    event RedeemPolicyIdUpdated(uint64 indexed newPolicyId);
    event CreateRateLimitConfigured(address indexed caller, uint256 maxAmount, uint256 interval);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `announcement`. Held separately so a 24/7
    ///         disclosure team can post announcements without holding
    ///         supply-changing or admin authority.
    function ANNOUNCE_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement. The announcement does
    ///         not store its `description` or `uri` on-chain (per current
    ///         design, see DESIGN_NOTES); the data lives only in the emitted
    ///         event log. The `id` is consumed: subsequent calls in the
    ///         same transaction that reference this `id` are gated on it
    ///         having been announced first; subsequent calls in later
    ///         transactions may not reuse it.
    /// @dev    Requires `ANNOUNCE_ROLE`. Reverts with
    ///         `AnnouncementIdAlreadyUsed` on `id` reuse.
    function announcement(string calldata id, string calldata description, string calldata uri) external;

    /// @notice Whether the given announcement ID has been consumed.
    function isAnnouncementIdUsed(string calldata id) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              SHARE RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice The current token-to-share ratio. A 1:1 ratio (numerator ==
    ///         denominator) means raw token balances equal share counts.
    ///         A 2:1 ratio (e.g. after a 2-for-1 split) means each raw
    ///         token represents 2 shares.
    function shareRatio() external view returns (uint48 numerator, uint48 denominator);

    /// @notice Converts a raw token balance to its current share count via
    ///         the active share ratio. Equivalent to
    ///         `balance * denominator / numerator`.
    function toShares(uint256 balance) external view returns (uint256);

    /// @notice Convenience: `toShares(balanceOf(account))`.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Sets a new share ratio (typically following an off-chain
    ///         stock split or reverse split). Holder balances are NOT
    ///         rewritten; the displayed share count derives from the new
    ///         ratio at read time, preserving DeFi composability.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction with the same id.
    ///         Both numerator and denominator must be non-zero.
    function updateShareRatio(string calldata announcementId, uint48 newNumerator, uint48 newDenominator) external;

    /*//////////////////////////////////////////////////////////////
                          ISSUANCE: create
    //////////////////////////////////////////////////////////////*/

    /// @notice The compliant issuance path. Mints `amount` to `to` subject
    ///         to the standard transfer-policy mint-recipient check AND to a
    ///         per-caller rate limit configured by the admin.
    /// @dev    Requires `ISSUER_ROLE`. Subject to the inherited supply cap
    ///         (`supplyCap`). Distinct from the inherited `mint` semantically
    ///         because securities have legal definitions around what
    ///         constitutes "creation"; this is the function product surfaces
    ///         should call. Tokens that want to disable normal issuance after
    ///         a bootstrap period can revoke `ISSUER_ROLE` from all callers.
    function create(address to, uint256 amount) external;

    /// @notice The remaining create allowance for `caller` under their
    ///         current rate-limit configuration.
    function createAllowance(address caller) external view returns (uint256);

    /// @notice Configures the per-call create rate limit for `caller`:
    ///         `maxAmount` total over each `interval` (seconds).
    /// @dev    Requires `DEFAULT_ADMIN_ROLE`. Setting `maxAmount` to 0 or
    ///         interval to 0 effectively disables that caller's create.
    function configureCreateRateLimit(address caller, uint256 maxAmount, uint256 interval) external;

    /*//////////////////////////////////////////////////////////////
                       ISSUANCE: cold-path batch
    //////////////////////////////////////////////////////////////*/

    /// @notice Cold-path batch mint. Used for unusual or emergency issuance
    ///         (e.g. distribution of a stock dividend to many holders). All
    ///         recipients must satisfy `isAuthorizedMintRecipient` on the
    ///         active transfer policy.
    /// @dev    Requires `ISSUER_ROLE` and an `Announcement(id, ...)` emitted
    ///         earlier in the same transaction with the same `announcementId`.
    ///         Subject to the inherited `supplyCap`. Reverts atomically if
    ///         any single recipient fails; partial mints are not possible.
    function adminMint(
        string calldata announcementId,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    /// @notice Cold-path batch burn. Used for cold-path corporate actions
    ///         (reverse-tender settlement, mass-corrections under regulatory
    ///         direction, etc.). NOT subject to the contract pause: admins
    ///         can adminBurn even while transfers are paused.
    /// @dev    Requires `BURN_BLOCKED_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction with the same
    ///         `announcementId`. Reverts atomically if any single account
    ///         lacks sufficient balance.
    function adminBurn(
        string calldata announcementId,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;

    /*//////////////////////////////////////////////////////////////
                             USER REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @notice User-initiated burn for off-chain settlement. The caller
    ///         destroys `amount` of their own balance in exchange for the
    ///         off-chain commitment to settle the equivalent shares to
    ///         their brokerage account.
    /// @dev    Requires the caller to be authorized under the token's
    ///         current `redeemPolicyId` (typically a Coinbase-managed
    ///         allowlist of KYC'd, brokerage-connected accounts). Reverts
    ///         with `RedeemBelowMinimum` if `amount < minimumRedeemable`.
    function redeem(uint256 amount) external;

    /// @notice The minimum amount that can be redeemed in a single call.
    ///         Set by the admin to amortize per-redeem off-chain settlement
    ///         overhead.
    function minimumRedeemable() external view returns (uint256);

    /// @notice Updates `minimumRedeemable`. Requires `DEFAULT_ADMIN_ROLE`.
    function setMinimumRedeemable(uint256 newMinimum) external;

    /// @notice The policy ID gating who can call `redeem`. Distinct from
    ///         `transferPolicyId`; the redeem allowlist is typically more
    ///         restrictive (only brokerage-verified accounts), while
    ///         transfers may permit a broader set of holders.
    /// @dev    The policy referenced here should be a simple WHITELIST
    ///         policy in the registry, with admin held by whoever manages
    ///         the brokerage onboarding pipeline (typically the issuer).
    function redeemPolicyId() external view returns (uint64);

    /// @notice Updates `redeemPolicyId`. Requires `DEFAULT_ADMIN_ROLE`.
    function setRedeemPolicyId(uint64 newPolicyId) external;

    /*//////////////////////////////////////////////////////////////
                       SECURITY IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the value of the named identifier (e.g. ISIN, CUSIP,
    ///         FIGI). Returns the empty string if not set.
    function securityIdentifier(string calldata identifierType) external view returns (string memory);

    /// @notice Returns all currently-set identifiers as `[type, value]`
    ///         pairs. Order is not guaranteed; callers should treat the
    ///         array as a set. The expected count is small (a handful per
    ///         security), so enumeration is safe.
    function getSecurityIdentifiers() external view returns (string[2][] memory);

    /// @notice Sets, updates, or removes a security identifier. If `remove`
    ///         is true, the entry is deleted (`value` is ignored).
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction. Reverts with
    ///         `InvalidIdentifierType` on empty `identifierType`.
    function updateSecurityIdentifier(
        string calldata announcementId,
        string calldata identifierType,
        string calldata value,
        bool remove
    ) external;

    /*//////////////////////////////////////////////////////////////
                       NAME / SYMBOL UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the token's name (e.g. corporate rebrand). Reads via
    ///         the inherited `name()` accessor reflect the new value
    ///         immediately. Affects EIP-712 domain separator computation
    ///         (used by `permit`); callers signing permits should re-read
    ///         `name()` immediately before signing.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction.
    function updateName(string calldata announcementId, string calldata newName) external;

    /// @notice Updates the token's symbol (e.g. ticker change). Reads via
    ///         the inherited `symbol()` accessor reflect the new value
    ///         immediately.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE` and an `Announcement(id, ...)`
    ///         emitted earlier in the same transaction.
    function updateSymbol(string calldata announcementId, string calldata newSymbol) external;
}
