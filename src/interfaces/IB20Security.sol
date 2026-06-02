// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title  IB20Security
/// @author Coinbase
///
/// @notice A B-20 token variant for tokenized securities. Extends `IB20` with announcements,
///         share-ratio accounting, batched mint for corporate actions, holder-initiated
///         redemption, and security-identifier metadata.
interface IB20Security is IB20 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice `announce` was called with an `id` that has already been consumed.
    error AnnouncementIdAlreadyUsed(string id);

    /// @notice `updateSecurityIdentifier` was called with an empty `identifierType`.
    error InvalidIdentifierType();

    /// @notice A batched function was called with parallel arrays of differing lengths.
    ///
    /// @param leftLen  Length of the first array argument.
    /// @param rightLen Length of the second array argument.
    error LengthMismatch(uint256 leftLen, uint256 rightLen);

    /// @notice A batched function was called with empty arrays.
    error EmptyBatch();

    /// @notice `redeem` / `redeemWithMemo` resolved to a share count of zero or below the active floor.
    ///
    /// @param shares  Computed share count (`amount * sharesToTokensRatio / WAD_PRECISION`).
    /// @param minimum Configured `minimumRedeemable`.
    error BelowMinimumRedeemable(uint256 shares, uint256 minimum);

    /// @notice An inner call dispatched by `announce` tried to re-invoke `announce`.
    error AnnouncementInProgress();

    /// @notice An inner call dispatched by `announce` was shorter than four bytes.
    ///
    /// @param call Offending raw calldata blob.
    error InternalCallMalformed(bytes call);

    /// @notice An inner call dispatched by `announce` reverted. The inner revert reason is not bubbled.
    ///
    /// @param call Offending raw calldata blob.
    error InternalCallFailed(bytes call);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted by `redeem` and `redeemWithMemo` immediately after the `Transfer` burn event.
    ///         `amt` is in tokens; the corresponding share count is `amt * sharesToTokensRatio / WAD_PRECISION`.
    event Redeemed(address indexed from, uint256 amt, uint256 sharesToTokensRatio);

    /// @notice Emitted by `updateMinimumRedeemable`.
    event MinimumRedeemableUpdated(address indexed caller, uint256 newMinimumRedeemable);

    /// @notice Emitted by `updateShareRatio`.
    event ShareRatioUpdated(uint256 sharesToTokensRatio);

    /// @notice Emitted by `updateSecurityIdentifier`. An empty `value` indicates removal.
    event SecurityIdentifierUpdated(string identifierType, string value);

    /// @notice Emitted by `announce` to open an announcement bracket.
    event Announcement(address indexed caller, string id, string description, string uri);

    /// @notice Emitted by `announce` to close the bracket opened by the paired `Announcement` with the same `id`.
    event EndAnnouncement(string id);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `announce`, `updateShareRatio`, and `updateSecurityIdentifier`.
    ///         `updateName` / `updateSymbol` remain gated by the inherited `METADATA_ROLE`.
    /// @return Role identifier.
    function SECURITY_OPERATOR_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              PRECISION
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed-point precision used to scale `sharesToTokensRatio`. Equal to `1e18`.
    /// @return Precision constant.
    function WAD_PRECISION() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          POLICY TYPE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy slot consulted against `msg.sender` on `redeem` and `redeemWithMemo`.
    /// @return Policy scope identifier.
    function REDEEM_SENDER_POLICY() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement and atomically dispatches each entry in
    ///         `internalCalls` via self-`delegatecall` (preserving `msg.sender`). Emits
    ///         `Announcement` then `EndAnnouncement` with the same `id`. Pass an empty
    ///         `internalCalls` for a pure disclosure.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `SECURITY_OPERATOR_ROLE`.
    /// @dev Reverts with `AnnouncementIdAlreadyUsed` when `id` has previously been consumed.
    /// @dev Reverts with `InternalCallMalformed` when an entry in `internalCalls` is shorter than four bytes.
    /// @dev Reverts with `AnnouncementInProgress` when an entry in `internalCalls` targets `announce` itself.
    /// @dev Reverts with `InternalCallFailed` when an entry in `internalCalls` reverts during the inner `delegatecall`.
    ///
    /// @param internalCalls ABI-encoded calldata blobs executed in order via self-`delegatecall`; may be empty.
    /// @param id            Caller-chosen announcement identifier; single-use over the token's lifetime.
    /// @param description   Human-readable summary of the announcement.
    /// @param uri           Off-chain URI containing the full announcement contents.
    function announce(
        bytes[] calldata internalCalls,
        string calldata id,
        string calldata description,
        string calldata uri
    ) external;

    /// @notice Whether `id` has previously been consumed by `announce`.
    ///
    /// @param id Announcement identifier to query.
    ///
    /// @return Whether `id` is used.
    function isAnnouncementIdUsed(string calldata id) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              SHARE RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice The current share-to-tokens ratio, scaled to `WAD_PRECISION`.
    /// @return Current ratio.
    function sharesToTokensRatio() external view returns (uint256);

    /// @notice Converts `balance` to its current share count: `balance * sharesToTokensRatio / WAD_PRECISION`.
    ///
    /// @param balance Token amount to convert.
    ///
    /// @return Share count at the current ratio.
    function toShares(uint256 balance) external view returns (uint256);

    /// @notice Convenience for `toShares(balanceOf(account))`.
    ///
    /// @param account Account whose share count is being queried.
    ///
    /// @return Share count.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Sets a new share ratio. Holder balances are not rewritten; displayed share counts
    ///         derive from the new ratio at read time. Emits `ShareRatioUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `SECURITY_OPERATOR_ROLE`.
    ///
    /// @param newSharesToTokensRatio New ratio scaled to `WAD_PRECISION`.
    function updateShareRatio(uint256 newSharesToTokensRatio) external;

    /*//////////////////////////////////////////////////////////////
                            BATCHED ISSUANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amounts[i]` to `recipients[i]` in one call. All-or-nothing: any element
    ///         revert unwinds the whole transaction. Emits `Transfer(address(0), recipients[i], amounts[i])`
    ///         per element.
    ///
    /// @dev Reverts with `ContractPaused(MINT)` when `MINT` is paused.
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `MINT_ROLE`.
    /// @dev Reverts with `LengthMismatch` when `recipients.length != amounts.length`.
    /// @dev Reverts with `EmptyBatch` when either array is empty.
    /// @dev Reverts with `InvalidReceiver` when any `recipients[i] == address(0)`.
    /// @dev Reverts with `PolicyForbids(MINT_RECEIVER_POLICY, ...)` when any recipient is not authorized.
    /// @dev Reverts with `SupplyCapExceeded` when the cumulative mint would exceed the cap.
    ///
    /// @param recipients Accounts receiving the minted tokens.
    /// @param amounts    Per-recipient amounts, parallel to `recipients`.
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external;

    /*//////////////////////////////////////////////////////////////
                              REDEMPTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Burns `amount` from the caller, recording intent to settle off-chain. Emits
    ///         `Transfer(caller, address(0), amount)` followed by `Redeemed`.
    ///
    /// @dev Reverts with `ContractPaused(REDEEM)` when `REDEEM` is paused. Strict — no factory-bootstrap bypass.
    /// @dev Reverts with `PolicyForbids(REDEEM_SENDER_POLICY, ...)` when the caller is not authorized.
    /// @dev Reverts with `BelowMinimumRedeemable` when the resolved share count is zero or below `minimumRedeemable`.
    /// @dev Reverts with `InsufficientBalance` when the caller's balance is below `amount`.
    ///
    /// @param amount Token amount to redeem from the caller's balance.
    function redeem(uint256 amount) external;

    /// @notice Same as `redeem`, plus emits `Memo` immediately after the `Transfer` event and
    ///         before `Redeemed`. A memo of `bytes32(0)` is permitted.
    ///
    /// @param amount Token amount to redeem from the caller's balance.
    /// @param memo   Off-chain memo payload.
    function redeemWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice Sets a new minimum-redeemable threshold in shares. Emits `MinimumRedeemableUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `DEFAULT_ADMIN_ROLE`.
    ///
    /// @param newMinimumRedeemable New minimum redeemable amount, in shares.
    function updateMinimumRedeemable(uint256 newMinimumRedeemable) external;

    /// @notice The current minimum-redeemable threshold, in shares.
    /// @return Current floor.
    function minimumRedeemable() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          SECURITY IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The value of the named identifier (e.g. ISIN, CUSIP, FIGI), or the empty string if not set.
    ///
    /// @param identifierType Identifier category.
    ///
    /// @return Current value, or the empty string.
    function securityIdentifier(string calldata identifierType) external view returns (string memory);

    /// @notice Sets, updates, or removes a security identifier. An empty `value` removes the entry.
    ///         Emits `SecurityIdentifierUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `SECURITY_OPERATOR_ROLE`.
    /// @dev Reverts with `InvalidIdentifierType` when `identifierType` is the empty string.
    ///
    /// @param identifierType Identifier category (e.g. "ISIN").
    /// @param value          New value, or empty string to remove.
    function updateSecurityIdentifier(string calldata identifierType, string calldata value) external;
}
