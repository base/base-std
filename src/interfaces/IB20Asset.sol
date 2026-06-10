// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title  IB20Asset
/// @author Coinbase
///
/// @notice A B-20 token variant for assets of all kinds. Extends `IB20` with announcements,
///         multiplier-based scaling, batched mint for bulk issuance, and extra-metadata
///         entries.
interface IB20Asset is IB20 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice `announce` was called with an `id` that has already been consumed.
    error AnnouncementIdAlreadyUsed(string id);

    /// @notice `updateExtraMetadata` was called with an empty `key`.
    error InvalidMetadataKey();

    /// @notice `updateMultiplier` was called with a zero multiplier.
    error InvalidMultiplier();

    /// @notice A batched function was called with parallel arrays of differing lengths.
    ///
    /// @param leftLen  Length of the first array argument.
    /// @param rightLen Length of the second array argument.
    error LengthMismatch(uint256 leftLen, uint256 rightLen);

    /// @notice A batched function was called with empty arrays.
    error EmptyBatch();

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

    /// @notice Emitted by `updateMultiplier`.
    event MultiplierUpdated(uint256 multiplier);

    /// @notice Emitted by `updateExtraMetadata`. An empty `value` indicates removal.
    event ExtraMetadataUpdated(string key, string value);

    /// @notice Emitted by `announce` to open an announcement bracket.
    event Announcement(address indexed caller, string id, string description, string uri);

    /// @notice Emitted by `announce` to close the bracket opened by the paired `Announcement` with the same `id`.
    event EndAnnouncement(string id);

    /*//////////////////////////////////////////////////////////////
                              ROLE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `announce` and `updateMultiplier`. The metadata setters
    ///         (`updateName`, `updateSymbol`, `updateExtraMetadata`) are gated by the
    ///         inherited `METADATA_ROLE` instead.
    /// @return Role constant.
    function OPERATOR_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              PRECISION
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed-point precision used to scale `multiplier`. Equal to `1e18`.
    /// @return Precision constant.
    function WAD_PRECISION() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement and atomically dispatches each entry in
    ///         `internalCalls` via self-`delegatecall` (preserving `msg.sender`). Emits
    ///         `Announcement` then `EndAnnouncement` with the same `id`. Pass an empty
    ///         `internalCalls` for a pure disclosure.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `OPERATOR_ROLE`.
    /// @dev Reverts with `AnnouncementIdAlreadyUsed` when `id` has previously been consumed.
    /// @dev Reverts with `InternalCallMalformed` when an entry in `internalCalls` is shorter than four bytes.
    /// @dev Reverts with `AnnouncementInProgress` when an entry in `internalCalls` targets `announce` itself.
    /// @dev Reverts with `InternalCallFailed` when an entry in `internalCalls` reverts during the inner `delegatecall`.
    ///
    /// @param internalCalls ABI-encoded calldata blobs executed in order via self-`delegatecall`; may be empty.
    /// @param id            Caller-chosen announcement id; single-use over the token's lifetime.
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
    /// @param id Announcement id to query.
    ///
    /// @return Whether `id` is used.
    function isAnnouncementIdUsed(string calldata id) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                               MULTIPLIER
    //////////////////////////////////////////////////////////////*/

    /// @notice The current multiplier, scaled to `WAD_PRECISION`. Holder balances are stored
    ///         as raw units; the multiplier scales them into a derived "scaled" view, similar
    ///         in shape to wstETH wrapping stETH.
    /// @return Current multiplier.
    function multiplier() external view returns (uint256);

    /// @notice Converts a raw balance to its scaled view: `rawBalance * multiplier / WAD_PRECISION`.
    ///
    /// @param rawBalance Raw token amount to scale.
    ///
    /// @return Scaled balance at the current multiplier.
    function toScaledBalance(uint256 rawBalance) external view returns (uint256);

    /// @notice Converts a scaled balance back to its raw representation:
    ///         `scaledBalance * WAD_PRECISION / multiplier`.
    ///
    /// @dev Integer division rounds toward zero; conversions are not exactly reversible when
    ///      `multiplier != WAD_PRECISION`. `toRawBalance(toScaledBalance(x))` may return a
    ///      value slightly less than `x`.
    ///
    /// @param scaledBalance Scaled token amount to convert back.
    ///
    /// @return rawBalance Raw balance at the current multiplier.
    function toRawBalance(uint256 scaledBalance) external view returns (uint256 rawBalance);

    /// @notice Convenience for `toScaledBalance(balanceOf(account))`.
    ///
    /// @param account Account whose scaled balance is being queried.
    ///
    /// @return Scaled balance.
    function scaledBalanceOf(address account) external view returns (uint256);

    /// @notice Sets a new multiplier. Holder raw balances are not rewritten; scaled balances
    ///         derive from the new multiplier at read time. Emits `MultiplierUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `OPERATOR_ROLE`.
    /// @dev Reverts with `InvalidMultiplier` when `newMultiplier` is zero.
    ///
    /// @param newMultiplier New multiplier scaled to `WAD_PRECISION`; must be non-zero.
    function updateMultiplier(uint256 newMultiplier) external;

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
                             EXTRA METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice The value of the named metadata entry, or the empty string if not set. A
    ///         variant-agnostic key/value store; the issuer chooses the key namespace
    ///         (e.g. `"category"`, `"region"`, `"reference"`).
    ///
    /// @param key Metadata entry key.
    ///
    /// @return Current value, or the empty string.
    function extraMetadata(string calldata key) external view returns (string memory);

    /// @notice Sets, updates, or removes an extra-metadata entry. An empty `value` removes the
    ///         entry. Emits `ExtraMetadataUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `METADATA_ROLE`.
    /// @dev Reverts with `InvalidMetadataKey` when `key` is the empty string.
    ///
    /// @param key   Metadata entry key (e.g. `"category"`).
    /// @param value New value, or empty string to remove.
    function updateExtraMetadata(string calldata key, string calldata value) external;
}
