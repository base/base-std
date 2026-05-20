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
///         2. `sharesToTokensRatio()` / `toShares(...)` / `sharesOf(...)`
///            plus `updateShareRatio(...)` for split-safe
///            DeFi-compatible share accounting.
///         3. `batchMint(address[],uint256[])` and
///            `batchBurn(address[],uint256[])` for the cold-path
///            corporate-actions issuance and seizure flows. These are
///            scoped to the security-token surface (not the base
///            `IB20`) because batched destruction of third-party
///            balances is a compliance-sensitive operation and the
///            batched issuance path is paired with the announcement
///            flow above. See the per-function natspec for role
///            gating; `batchBurn` is held tighter than `batchMint`.
///         4. `redeem(...)` / `redeemWithMemo(...)` plus
///            `updateMinimumRedeemable(...)` and `minimumRedeemable()`
///            for the holder-initiated off-chain settlement path.
///         5. `securityIdentifier(...)` / `updateSecurityIdentifier(...)`
///            for ISIN, CUSIP, FIGI, and similar off-chain registry IDs.
///
///         **Metadata updates.** The inherited `setName(...)` and
///         `setSymbol(...)` continue to be gated by `METADATA_ROLE`
///         from `IB20`; this interface does NOT re-gate them. Security
///         tokens that want the corporate-actions desk to be the sole
///         caller of these functions grant `METADATA_ROLE` only to
///         addresses that also hold `SECURITY_OPERATOR_ROLE`. That
///         pairing is operational, not contract-enforced.
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
    event Redeemed(address indexed from, uint256 amt, uint256 sharesToTokensRatio);

    /// @notice Emitted by `updateMinimumRedeemable` when the redemption
    ///         floor is changed.
    event MinimumRedeemableUpdated(uint256 newMinimumRedeemable);

    /// @notice Emitted by `updateShareRatio` when the share-to-tokens
    ///         ratio is changed.
    event ShareRatioUpdated(uint256 sharesToTokensRatio);

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

    /// @notice Required to call `announce`, `updateShareRatio`, and
    ///         `updateSecurityIdentifier`. Held separately from
    ///         `DEFAULT_ADMIN_ROLE` so corporate-actions operators can
    ///         be delegated without the broader admin powers (role
    ///         grants, policy changes, supply-cap changes, etc.).
    ///         `setName` / `setSymbol` are NOT gated by this role; they
    ///         are gated by the inherited `METADATA_ROLE` from `IB20`.
    ///         See the contract-level notes for the recommended
    ///         operational pairing.
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
    function sharesToTokensRatio() external view returns (uint256);

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
    function updateShareRatio(uint256 newSharesToTokensRatio) external;

    /*//////////////////////////////////////////////////////////////
                  BATCHED ISSUANCE AND CORP-ACTION SEIZURE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amounts[i]` tokens to `recipients[i]`. The
    ///         batched sibling of the inherited single-recipient
    ///         `IB20.mint(address,uint256)`; supports cold-path
    ///         issuance flows for corporate-actions events (initial
    ///         allocations, secondary issuances, etc.) that need to
    ///         land many recipients in one transaction.
    ///
    /// @dev    Requires `MINT_ROLE`. Subject to the `MINT_RECEIVER`
    ///         policy per recipient and to the `MINT` pause vector.
    ///         Reverts on length mismatch or empty arrays. Operators
    ///         should pair this with a separate `announce(...)` call
    ///         so the issuance is discoverable to indexers; this
    ///         interface does not enforce the pairing on-chain.
    ///
    /// @param  recipients Accounts receiving the minted tokens.
    /// @param  amounts    Per-recipient amounts, parallel to
    ///                    `recipients`.
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external;

    /// @notice Burns `amounts[i]` tokens from `accounts[i]`. The
    ///         batched sibling of the inherited
    ///         `IB20.burnBlocked(address,uint256)`; supports cold-path
    ///         compliance seizures (court-ordered claw-backs, sanctions
    ///         enforcement against multiple addresses, etc.) that need
    ///         to land many destructions in one transaction.
    ///
    /// @dev    Requires `BURN_ROLE`. Each `accounts[i]` MUST
    ///         currently be unauthorized under the active
    ///         `TRANSFER_SENDER` policy; otherwise reverts with
    ///         `AccountNotBlocked(accounts[i])`. Subject to the `BURN`
    ///         pause vector. Reverts on length mismatch or empty
    ///         arrays. Emits `Transfer(accounts[i], address(0),
    ///         amounts[i])` per element, Operators should pair this with
    ///         a separate `announce(...)` call so the seizure is
    ///         discoverable to indexers; this interface does not
    ///         enforce the pairing on-chain.
    ///
    /// @param  accounts Accounts whose balances will be debited. Each
    ///                  MUST be unauthorized under `TRANSFER_SENDER`.
    /// @param  amounts  Per-account amounts, parallel to `accounts`.
    function batchBurn(address[] calldata accounts, uint256[] calldata amounts) external;

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
    ///         `Redeemed`.
    ///
    /// @param  amount Token amount to redeem from the caller's balance.
    function redeem(uint256 amount) external;

    /// @notice Same as `redeem`, with a memo. Emits `Memo(memo)`
    ///         immediately after `Transfer()` and before `Redeemed`. 
    ///         See `IB20.transferWithMemo` for the memo convention; a memo
    ///         of `bytes32(0)` is permitted.
    function redeemWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice Sets a new minimum-redeemable threshold in shares.
    ///         `redeemShares` reverts if the resulting share amount would be
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
