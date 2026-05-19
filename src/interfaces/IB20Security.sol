// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IB20} from "./IB20.sol";

/// @title  IB20Security
/// @author Coinbase
/// @notice A B-20 token variant for tokenized securities (equities, ETFs,
///         commodities, etc.). Extends `IB20` with primitives specific to
///         securities: holder-impacting announcements, split-safe
///         share-ratio accounting, security-identifier metadata, batched
///         mint/burn for cold-path corporate actions, and a
///         holder-initiated redemption path for off-chain settlement.
///
/// @dev    **Inherited surface.** `IB20` already provides the pieces
///         shared across all B-20 variants: ERC-20 surface,
///         single-recipient `mint(address,uint256)` and `burn(uint256)`
///         (gated by `MINT_ROLE` and `BURN_ROLE`), memo'd siblings,
///         pause vectors (including `REDEEM`), permit, contract URI,
///         and OZ-style role management. Security tokens use all of
///         these as-is and do not redeclare them here.
///
///         **Security-specific additions.** This interface adds:
///         1. `announce(...)` plus `SECURITY_OPERATOR_ROLE` for posting
///            holder-impacting disclosures (corporate actions, name
///            changes, splits, etc.).
///         2. `shareRatio()` / `toShares(...)` / `sharesOf(...)` plus
///            `updateShareRatio(...)` for split-safe DeFi-compatible
///            share accounting.
///         3. `mint(address[],uint256[])` and `burn(address[],uint256[])`
///            batch functions for cold-path issuance and destruction.
///            These are distinct functions from the inherited
///            single-recipient `mint` and `burn`; they share the same
///            role gates (`MINT_ROLE` and `BURN_ROLE`) but operate on
///            arrays.
///         4. `redeem(...)` / `redeemWithMemo(...)` plus
///            `updateMinimumRedeemable(...)` and `minimumRedeemable()`
///            for the holder-initiated off-chain settlement path.
///         5. `securityIdentifier(...)` / `updateSecurityIdentifier(...)`
///            for ISIN, CUSIP, FIGI, and similar off-chain registry IDs.
///
///         **Re-gated inherited functions.** Implementations re-gate the
///         inherited `setName(...)` and `setSymbol(...)` from `IB20` so
///         that on a security token they require
///         `SECURITY_OPERATOR_ROLE` (not `DEFAULT_ADMIN_ROLE`). Name
///         and symbol updates on a security token are corporate
///         actions and follow the same operator path as `announce`,
///         `updateShareRatio`, and `updateSecurityIdentifier`.
///
///         **Announcement pairing.** The corporate-actions operator is
///         expected to post an `announce(...)` alongside each
///         state-changing operator call (`updateShareRatio`,
///         `updateSecurityIdentifier`, `setName`, `setSymbol`) so that
///         indexers can correlate the on-chain change with its
///         off-chain disclosure. This interface does NOT enforce that
///         pairing on-chain.
interface IB20Security is IB20 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice The supplied `id` has previously been consumed by
    ///         `announce`. Each announcement id may be used at most
    ///         once over the lifetime of the token.
    error AnnouncementIdAlreadyUsed(string id);

    /// @notice `updateSecurityIdentifier` was called with an empty
    ///         `identifierType` string. The category name is always
    ///         required; pass the empty string in `value` to remove an
    ///         entry instead.
    error InvalidIdentifierType();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted by `redeem` and `redeemWithMemo` when a holder
    ///         redeems tokens. `amt` is in tokens; the corresponding
    ///         share amount is `amt * sharesToTokensRatio /
    ///         WAD_PRECISION`.
    event SharesRedeemed(address indexed from, uint256 amt, uint128 sharesToTokensRatio);

    /// @notice Emitted by `updateMinimumRedeemable` when the redemption
    ///         floor is changed.
    event MinimumRedeemableUpdated(uint256 newMinimumRedeemable);

    /// @notice Emitted by `updateShareRatio` when the share-to-tokens
    ///         ratio is changed.
    event ShareRatioUpdated(uint128 sharesToTokensRatio);

    /// @notice Emitted by `updateSecurityIdentifier` when an identifier
    ///         entry is set, updated, or removed. An empty `value`
    ///         indicates removal.
    event IdentifierUpdated(string identifierType, string value);

    /// @notice Emitted by `announce` when a holder-impacting disclosure
    ///         is posted. Indexers join this with subsequent
    ///         security-token state changes via `id`.
    event Announcement(address indexed caller, string id, string description, string uri);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `announce`, `updateShareRatio`,
    ///         `updateSecurityIdentifier`, and the re-gated inherited
    ///         `setName` and `setSymbol`. Held separately from
    ///         `DEFAULT_ADMIN_ROLE` so corporate-actions operators can
    ///         be delegated without the broader admin powers (role
    ///         grants, policy changes, supply-cap changes, etc.).
    function SECURITY_OPERATOR_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          POLICY TYPE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The policy slot consulted against `msg.sender` on
    ///         `redeem` and `redeemWithMemo`. Identifier is
    ///         `keccak256("REDEEMER_SENDER")`.
    function REDEEMER_SENDER() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement. Each `id` may be
    ///         consumed at most once over the lifetime of the token;
    ///         subsequent calls that reuse `id` revert with
    ///         `AnnouncementIdAlreadyUsed`.
    ///
    /// @dev    Requires `SECURITY_OPERATOR_ROLE`. Emits `Announcement`.
    ///
    /// @param  id          Caller-chosen announcement identifier.
    /// @param  description Human-readable summary of the announcement.
    /// @param  uri         Off-chain URI containing the full
    ///                     announcement contents.
    function announce(string calldata id, string calldata description, string calldata uri) external;

    /// @notice Returns true if `id` has previously been consumed by
    ///         `announce`.
    function isAnnouncementIdUsed(string calldata id) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                              SHARE RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice The current share-to-tokens ratio, scaled to the
    ///         implementation's `WAD_PRECISION`.
    function shareRatio() external view returns (uint128 sharesToTokensRatio);

    /// @notice Converts a raw token balance to its current share count
    ///         via the active share ratio:
    ///         `balance * sharesToTokensRatio / WAD_PRECISION`.
    function toShares(uint256 balance) external view returns (uint256);

    /// @notice Convenience: `toShares(balanceOf(account))`.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Sets a new share ratio (typically following an off-chain
    ///         stock split or reverse split). Holder balances are NOT
    ///         rewritten; the displayed share count derives from the
    ///         new ratio at read time, preserving DeFi composability.
    ///
    /// @dev    Requires `SECURITY_OPERATOR_ROLE`. Emits
    ///         `ShareRatioUpdated`. Operators should pair this with a
    ///         separate `announce(...)` call so the change is
    ///         discoverable to indexers; this interface does not
    ///         enforce the pairing on-chain.
    ///
    /// @param  newSharesToTokensRatio The new ratio scaled to
    ///                                `WAD_PRECISION`.
    function updateShareRatio(uint128 newSharesToTokensRatio) external;

    /*//////////////////////////////////////////////////////////////
                       BATCHED ISSUANCE AND BURN
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amounts[i]` tokens to `recipients[i]`. Distinct
    ///         from the inherited single-recipient
    ///         `mint(address,uint256)`; this batched form supports the
    ///         cold-path issuance flow for corporate actions.
    ///
    /// @dev    Requires `MINT_ROLE`. Subject to the `MINT_RECEIVER`
    ///         policy per recipient and to the `MINT` pause vector.
    ///         Reverts on length mismatch or empty arrays.
    ///
    /// @param  recipients Accounts receiving the minted tokens.
    /// @param  amounts    Per-recipient amounts, parallel to
    ///                    `recipients`.
    function mint(address[] calldata recipients, uint256[] calldata amounts) external;

    /// @notice Burns `amounts[i]` tokens from `accounts[i]`. Distinct
    ///         from the inherited self-burn `burn(uint256)`; this
    ///         batched form requires `BURN_ROLE` and operates on
    ///         third-party balances for cold-path destruction.
    ///
    /// @dev    Requires `BURN_ROLE`. Subject to the `BURN` pause
    ///         vector. Reverts on length mismatch or empty arrays.
    ///
    /// @param  accounts Accounts whose balances will be debited.
    /// @param  amounts  Per-account amounts, parallel to `accounts`.
    function burn(address[] calldata accounts, uint256[] calldata amounts) external;

    /*//////////////////////////////////////////////////////////////
                              REDEMPTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Burns `amount` tokens from the caller, recording intent
    ///         to settle off-chain.
    ///
    /// @dev    Subject to the `REDEEMER_SENDER` policy and to the
    ///         `REDEEM` pause vector. Reverts when the corresponding
    ///         share amount (`amount * sharesToTokensRatio /
    ///         WAD_PRECISION`) is below `minimumRedeemable`. Emits
    ///         `SharesRedeemed`.
    ///
    /// @param  amount Token amount to redeem from the caller's balance.
    function redeem(uint256 amount) external;

    /// @notice Same as `redeem`, with a memo. Emits `Memo(memo)`
    ///         immediately after `SharesRedeemed`. See
    ///         `IB20.transferWithMemo` for the memo convention; a memo
    ///         of `bytes32(0)` is permitted.
    function redeemWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice Sets a new minimum-redeemable threshold in shares.
    ///         `redeem` reverts if the resulting share amount would be
    ///         below this value.
    ///
    /// @dev    Requires `DEFAULT_ADMIN_ROLE`. Emits
    ///         `MinimumRedeemableUpdated`.
    ///
    /// @param  newMinimumRedeemable New minimum redeemable amount, in
    ///                              shares.
    function updateMinimumRedeemable(uint256 newMinimumRedeemable) external;

    /// @notice The current minimum-redeemable threshold, in shares.
    function minimumRedeemable() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          SECURITY IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the value of the named identifier (e.g. ISIN,
    ///         CUSIP, FIGI). Returns the empty string if not set.
    function securityIdentifier(string calldata identifierType) external view returns (string memory);

    /// @notice Sets, updates, or removes a security identifier. Passing
    ///         an empty `value` removes the entry; passing a non-empty
    ///         `value` sets or overwrites it.
    ///
    /// @dev    Requires `SECURITY_OPERATOR_ROLE`. Emits
    ///         `IdentifierUpdated`. Reverts with `InvalidIdentifierType`
    ///         if `identifierType` is the empty string. Operators
    ///         should pair this with a separate `announce(...)` call;
    ///         this interface does not enforce the pairing on-chain.
    ///
    /// @param  identifierType Identifier category (e.g. "ISIN").
    /// @param  value          New value, or empty string to remove.
    function updateSecurityIdentifier(string calldata identifierType, string calldata value) external;
}
