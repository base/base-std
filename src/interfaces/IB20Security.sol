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
///         1. `announce(bytes[],string,string,string)` plus
///            `SECURITY_OPERATOR_ROLE`. The single canonical wrapper
///            for posting a holder-impacting disclosure AND atomically
///            executing the on-chain calls it discloses; see
///            "Announcement pairing" below for the topology.
///         2. `sharesToTokensRatio()` / `toShares(...)` / `sharesOf(...)`
///            plus `updateShareRatio(...)` for split-safe
///            DeFi-compatible share accounting.
///         3. `batchMint(address[],uint256[])` and
///            `batchBurn(address[],uint256[])` for the cold-path
///            corporate-actions issuance and clawback flows. These are
///            scoped to the security-token surface (not the base
///            `IB20`) because batched destruction of third-party
///            balances is a compliance-sensitive operation and the
///            batched issuance path is the natural target of the
///            announcement bracket above. See the per-function
///            natspec for role gating; `batchBurn` is held tighter
///            than `batchMint`.
///         4. `redeem(...)` / `redeemWithMemo(...)` plus
///            `updateMinimumRedeemable(...)` and `minimumRedeemable()`
///            for the holder-initiated off-chain settlement path.
///         5. `securityIdentifier(...)` / `updateSecurityIdentifier(...)`
///            for ISIN, CUSIP, FIGI, and similar off-chain registry IDs.
///
///         **EIP-712 domain.** Inherited unchanged from `IB20`: the
///         domain binds `(name, version, chainId, verifyingContract)`,
///         the inherited `updateName(...)` emits `NameUpdated` followed
///         by `EIP712DomainChanged()` (in that order), and outstanding
///         off-chain `permit` signatures issued under a previous `name`
///         cease to be valid as soon as `updateName` lands. See the
///         base `IB20` "Permit" notes for the full rationale; this
///         variant does not override any part of the domain.
///
///         **Metadata updates.** The inherited `updateName(...)` and
///         `updateSymbol(...)` continue to be gated by `METADATA_ROLE`
///         from `IB20`; this interface does NOT re-gate them. Security
///         tokens that want the corporate-actions desk to be the sole
///         caller of these functions grant `METADATA_ROLE` only to
///         addresses that also hold `SECURITY_OPERATOR_ROLE`. That
///         pairing is operational, not contract-enforced. The standard
///         way to issue a name or symbol change is to wrap the
///         `updateName` / `updateSymbol` call as an entry in
///         `announce(...)`'s `internalCalls`, so the rebrand lands in
///         the same `Announcement` ↔ `EndAnnouncement` bracket as the
///         disclosure that explains it.
///
///         **Announcement pairing.** Every state-changing operator
///         call that affects holder-visible token semantics
///         (`updateShareRatio`, `updateSecurityIdentifier`, `updateName`,
///         `updateSymbol`, `updateContractURI`, `batchMint`, `batchBurn`,
///         and admin-level changes such as `updatePolicy` /
///         `updateSupplyCap` / `pause` / `unpause`) SHOULD be issued by
///         encoding the call into the `internalCalls` parameter of
///         `announce(...)`. The token then:
///         1. emits `Announcement(caller, id, description, uri)`,
///         2. `delegatecall`s each entry in `internalCalls` with
///            `msg.sender` preserved (so the operator's own roles
///            apply to the inner calls), reverting the entire
///            announce if any inner call reverts, and
///         3. emits `EndAnnouncement(id)`.
///         This binds every change to its off-chain disclosure
///         atomically: indexers never see a `Transfer`, a
///         `ShareRatioUpdated`, or any other state-mutation event
///         from a wrapped call without the surrounding bracket, and
///         they never see a half-applied bracket because any inner
///         revert unwinds the entire transaction including the
///         `Announcement` event.
///
///         The bare functions remain individually callable by their
///         role holders for emergency operator override, but
///         unwrapped invocations produce no bracket events and so are
///         indistinguishable from any other state mutation in the log
///         stream. Production corporate-actions flows are expected to
///         go through `announce(...)`; standalone calls are an escape
///         hatch, not the standard path. Recursion (an inner call
///         re-invoking `announce`) reverts with
///         `AnnouncementInProgress` so the bracket is always exactly
///         one level deep.
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

    /// @notice A batched function (`batchMint`, `batchBurn`) was called
    ///         with parallel arrays of differing lengths. The two
    ///         lengths are reported verbatim in the order the function
    ///         declares them (`recipients`/`amounts` for `batchMint`;
    ///         `accounts`/`amounts` for `batchBurn`).
    error LengthMismatch(uint256 leftLen, uint256 rightLen);

    /// @notice A batched function (`batchMint`, `batchBurn`) was called
    ///         with empty arrays. Empty batches are rejected so the
    ///         caller cannot accidentally emit a no-op corp-actions
    ///         transaction.
    error EmptyBatch();

    /// @notice `redeem` / `redeemWithMemo` was called with an `amount`
    ///         that resolves to a share count below the active redemption
    ///         floor. `shares` is the computed share count
    ///         (`amount * sharesToTokensRatio / WAD_PRECISION`);
    ///         `minimum` is the configured `minimumRedeemable`. Also
    ///         emitted when the resulting share count is zero (which is
    ///         always rejected, regardless of `minimumRedeemable`).
    error BelowMinimumRedeemable(uint256 shares, uint256 minimum);

    /// @notice Reverted by `announce` when one of its `internalCalls`
    ///         tries to invoke `announce` itself. The recursion guard
    ///         keeps the bracketing topology one level deep:
    ///         exactly one `Announcement` and one matching
    ///         `EndAnnouncement` per outer call, with no nesting.
    ///         Indexers can therefore treat every `Announcement` log
    ///         as the unambiguous start of a single bracket pairing.
    error AnnouncementInProgress();

    /// @notice Reverted by `announce` when one of its `internalCalls`
    ///         is malformed (shorter than four bytes, no function
    ///         selector to validate). Carries the offending raw
    ///         calldata blob.
    error InternalCallMalformed(bytes call);

    /// @notice Reverted by `announce` when one of its `internalCalls`
    ///         reverts during the inner `delegatecall`. Carries the
    ///         offending raw calldata blob; the inner revert reason
    ///         is intentionally not bubbled through so this error
    ///         identifies the wrapped call deterministically. To debug
    ///         a failing inner call, replay it as a direct invocation
    ///         and read its native revert.
    error InternalCallFailed(bytes call);

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
    event MinimumRedeemableUpdated(address indexed caller, uint256 newMinimumRedeemable);

    /// @notice Emitted by `updateShareRatio` when the share-to-tokens
    ///         ratio is changed.
    event ShareRatioUpdated(uint256 sharesToTokensRatio);

    /// @notice Emitted by `updateSecurityIdentifier` when an identifier
    ///         entry is set, updated, or removed. An empty `value`
    ///         indicates removal.
    event SecurityIdentifierUpdated(string identifierType, string value);

    /// @notice Emitted by `announce` when a holder-impacting disclosure
    ///         is posted. Indexers join this with subsequent
    ///         security-token state changes via `id`.
    event Announcement(address indexed caller, string id, string description, string uri);

    /// @notice Emitted by `announce` immediately after every entry in
    ///         `internalCalls` has executed successfully (or
    ///         immediately after `Announcement` itself for a pure
    ///         announcement with `internalCalls.length == 0`).
    ///         Carries the same `id` as the paired `Announcement` so
    ///         indexers can join start ↔ end on the id even when
    ///         scanning logs in isolation. The recursion guard
    ///         (`AnnouncementInProgress`) makes the pairing
    ///         within-tx unambiguous; the `id` field hardens cross-tx
    ///         indexing as well.
    event EndAnnouncement(string id);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `announce`, `updateShareRatio`, and
    ///         `updateSecurityIdentifier`. Held separately from
    ///         `DEFAULT_ADMIN_ROLE` so corporate-actions operators can
    ///         be delegated without the broader admin powers (role
    ///         grants, policy changes, supply-cap changes, etc.).
    ///         `updateName` / `updateSymbol` are NOT gated by this role; they
    ///         are gated by the inherited `METADATA_ROLE` from `IB20`.
    ///         See the contract-level notes for the recommended
    ///         operational pairing.
    function SECURITY_OPERATOR_ROLE() external view returns (bytes32);

    /// @notice Required to call `batchBurn`. Held separately from
    ///         `BURN_ROLE` (which gates burn-of-self) and from
    ///         `BURN_BLOCKED_ROLE` (which gates seizure of
    ///         policy-blocked accounts) so the authority to destroy
    ///         third-party balances WITHOUT a blocked-status precondition
    ///         can be delegated narrowly to the corporate-actions desk
    ///         for clawbacks, consolidations, and similar batched
    ///         destructions. Tokens that do not need a batched-clawback
    ///         path simply never grant this role.
    function BURN_FROM_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              PRECISION
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed-point precision used to scale `sharesToTokensRatio`.
    ///         Equal to `1e18` (one WAD). Exposed on the ABI so callers
    ///         that read `sharesToTokensRatio()` directly can interpret
    ///         the value without hardcoding the constant; typical
    ///         callers should prefer `toShares(...)` / `sharesOf(...)`,
    ///         which apply the precision internally.
    function WAD_PRECISION() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          POLICY TYPE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The policy slot consulted against `msg.sender` on
    ///         `redeem` and `redeemWithMemo`. Identifier is
    ///         `keccak256("REDEEM_SENDER_POLICY")`.
    function REDEEM_SENDER_POLICY() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              ANNOUNCEMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Posts a holder-impacting announcement and, in the same
    ///         transaction, atomically executes the on-chain calls
    ///         that the announcement describes. Each `id` may be
    ///         consumed at most once over the lifetime of the token;
    ///         subsequent calls that reuse `id` revert with
    ///         `AnnouncementIdAlreadyUsed`.
    ///
    ///         Pass `internalCalls` as an empty array for a pure
    ///         disclosure (no on-chain change to bracket); pass one
    ///         or more ABI-encoded calldata blobs to bracket the
    ///         corresponding state changes inside the announcement.
    ///         For example, to disclose and execute a 2-for-1 split
    ///         in one transaction:
    ///
    ///             announce({
    ///                 internalCalls: [
    ///                     abi.encodeCall(this.updateShareRatio, (newRatio))
    ///                 ],
    ///                 id: "2026-Q3-split",
    ///                 description: "2-for-1 forward stock split",
    ///                 uri: "https://disclosures.example.com/...",
    ///             });
    ///
    /// @dev    Requires `SECURITY_OPERATOR_ROLE`. Topology:
    ///         1. Marks `id` consumed and emits
    ///            `Announcement(msg.sender, id, description, uri)`.
    ///         2. For each `internalCalls[i]`:
    ///            a. Validates the embedded function selector. Calls
    ///               shorter than four bytes revert with
    ///               `InternalCallMalformed(internalCalls[i])`. Calls
    ///               whose selector is `announce` itself revert with
    ///               `AnnouncementInProgress` so the bracket cannot
    ///               nest.
    ///            b. Issues `address(this).delegatecall(internalCalls[i])`,
    ///               which preserves `msg.sender` so role checks on
    ///               the inner function see the operator (not the
    ///               token contract). On failure, reverts with
    ///               `InternalCallFailed(internalCalls[i])`; the
    ///               inner revert reason is intentionally not bubbled
    ///               (replay the call directly to debug).
    ///         3. Emits `EndAnnouncement(id)`.
    ///
    ///         Atomicity: any inner-call revert (including
    ///         `InternalCallFailed`, `InternalCallMalformed`, or
    ///         `AnnouncementInProgress`) unwinds the entire
    ///         transaction, so no `Announcement` event is observable
    ///         without its matching `EndAnnouncement`.
    ///
    ///         The inner functions invoked through `internalCalls`
    ///         are subject to their normal authorization gates (role
    ///         checks, policy checks, pause vectors); the announcement
    ///         wrapper does not add or relax any of them. The
    ///         operator therefore needs both `SECURITY_OPERATOR_ROLE`
    ///         (to call `announce`) and whatever role each inner
    ///         function requires (e.g. `MINT_ROLE` for `batchMint`,
    ///         `METADATA_ROLE` for `updateName`).
    ///
    /// @param  internalCalls ABI-encoded calldata blobs executed
    ///                       in-order via self-`delegatecall`. May
    ///                       be empty (pure disclosure).
    /// @param  id            Caller-chosen announcement identifier;
    ///                       single-use over the token's lifetime.
    /// @param  description   Human-readable summary of the
    ///                       announcement.
    /// @param  uri           Off-chain URI containing the full
    ///                       announcement contents.
    function announce(
        bytes[] calldata internalCalls,
        string calldata id,
        string calldata description,
        string calldata uri
    ) external;

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
    ///         `ShareRatioUpdated`. Standard usage is to invoke this
    ///         through `announce(...)`'s `internalCalls`, which
    ///         brackets the ratio change with a matching disclosure
    ///         atomically (see the contract-level "Announcement
    ///         pairing" notes). Direct invocation by a role holder
    ///         remains permitted for emergency override but produces
    ///         no `Announcement` / `EndAnnouncement` bracket.
    ///
    /// @param  newSharesToTokensRatio The new ratio scaled to
    ///                                `WAD_PRECISION`.
    function updateShareRatio(uint256 newSharesToTokensRatio) external;

    /*//////////////////////////////////////////////////////////////
                  BATCHED ISSUANCE AND CORP-ACTION CLAWBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amounts[i]` tokens to `recipients[i]`. The
    ///         batched sibling of the inherited single-recipient
    ///         `IB20.mint(address,uint256)`; supports cold-path
    ///         issuance flows for corporate-actions events (initial
    ///         allocations, secondary issuances, etc.) that need to
    ///         land many recipients in one transaction.
    ///
    /// @dev    Reverts in the following canonical order (first violated
    ///         check wins):
    ///         1. `ContractPaused(MINT)` if `MINT` is paused.
    ///         2. `AccessControlUnauthorizedAccount(msg.sender, MINT_ROLE)`
    ///            if the caller does not hold `MINT_ROLE`.
    ///         3. `LengthMismatch(recipients.length, amounts.length)` if
    ///            the parallel arrays disagree.
    ///         4. `EmptyBatch()` if either array is empty.
    ///         5..N. Per-element checks inside the loop: `InvalidReceiver`,
    ///               `PolicyForbids(MINT_RECEIVER_POLICY, ...)`,
    ///               `SupplyCapExceeded` — see `mint`'s natspec for the
    ///               per-element precedence.
    ///         The pause and role gates are evaluated ONCE for the
    ///         whole batch (entrypoint modifiers); per-element gates
    ///         fire per recipient inside the loop.
    ///         All-or-nothing: if any element reverts, the entire
    ///         transaction reverts and no partial state is committed.
    ///         Emits `Transfer(address(0), recipients[i], amounts[i])`
    ///         per element. Standard usage is to invoke this through
    ///         `announce(...)`'s `internalCalls`, which brackets the
    ///         issuance with a matching disclosure atomically (see
    ///         the contract-level "Announcement pairing" notes).
    ///         Direct invocation by a role holder remains permitted
    ///         for emergency override but produces no `Announcement` /
    ///         `EndAnnouncement` bracket.
    ///
    /// @param  recipients Accounts receiving the minted tokens.
    /// @param  amounts    Per-recipient amounts, parallel to
    ///                    `recipients`.
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external;

    /// @notice Burns `amounts[i]` tokens from `accounts[i]`. Distinct
    ///         from the inherited `IB20.burnBlocked(address,uint256)`:
    ///         where `burnBlocked` exists for sanctions-style seizure
    ///         and refuses to operate against accounts that are still
    ///         authorized under `TRANSFER_SENDER_POLICY`, `batchBurn` is the
    ///         general corporate-actions clawback path and operates
    ///         unconditionally on the supplied accounts. Supports
    ///         cold-path consolidations, redemptions-in-kind, and
    ///         court-ordered destructions that need to land many
    ///         debits in one transaction without first arranging for
    ///         each account to be policy-blocked.
    ///
    /// @dev    `BURN_FROM_ROLE` is enforced WITHOUT the factory-bootstrap
    ///         bypass — clawback against existing balances has no
    ///         init-time use case, so the role check is unconditional.
    ///         NOT gated by any policy: the corporate-actions desk is
    ///         trusted to pick the right set of accounts off-chain, and
    ///         the role grant is the on-chain authorization. Reverts in
    ///         the following canonical order (first violated check wins):
    ///         1. `ContractPaused(BURN)` if `BURN` is paused.
    ///         2. `AccessControlUnauthorizedAccount(msg.sender, BURN_FROM_ROLE)`
    ///            if the caller does not hold `BURN_FROM_ROLE`.
    ///         3. `LengthMismatch(accounts.length, amounts.length)` if
    ///            the parallel arrays disagree.
    ///         4. `EmptyBatch()` if either array is empty.
    ///         5. Per-element `InsufficientBalance(accounts[k], balance,
    ///            amounts[k])` from `_burnRaw`.
    ///         All-or-nothing: if any element reverts, the entire
    ///         transaction reverts and no partial state is committed.
    ///         Emits `Transfer(accounts[i], address(0), amounts[i])`
    ///         per element; does NOT emit `BurnedBlocked` (that event
    ///         is reserved for `burnBlocked`'s sanctions semantics).
    ///         Standard usage is to invoke this through `announce(...)`'s
    ///         `internalCalls`, which brackets the clawback with a
    ///         matching disclosure atomically (see the contract-level
    ///         "Announcement pairing" notes). Direct invocation by a
    ///         role holder remains permitted for emergency override but
    ///         produces no `Announcement` / `EndAnnouncement` bracket.
    ///
    /// @param  accounts Accounts whose balances will be debited.
    /// @param  amounts  Per-account amounts, parallel to `accounts`.
    function batchBurn(address[] calldata accounts, uint256[] calldata amounts) external;

    /*//////////////////////////////////////////////////////////////
                              REDEMPTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Burns `amount` tokens from the caller, recording intent
    ///         to settle off-chain.
    ///
    /// @dev    Reverts in the following canonical order (first violated
    ///         check wins):
    ///         1. `ContractPaused(REDEEM)` if `REDEEM` is paused.
    ///            Enforced WITHOUT the factory-bootstrap bypass — redeem
    ///            is a holder-initiated path with no legitimate init-time
    ///            use case.
    ///         2. `PolicyForbids(REDEEM_SENDER_POLICY, policyId)` if
    ///            `msg.sender` is not authorized under the active
    ///            `REDEEM_SENDER_POLICY` policy.
    ///         3. `BelowMinimumRedeemable(shares, minimumRedeemable)` if
    ///            the corresponding share amount (`amount *
    ///            sharesToTokensRatio / WAD_PRECISION`) is zero OR is
    ///            strictly less than `minimumRedeemable`. Zero-share
    ///            redemptions are always rejected, regardless of
    ///            `minimumRedeemable`'s configured value, so a holder
    ///            cannot burn token dust that resolves to no shares.
    ///         4. `InsufficientBalance(caller, balance, amount)` if the
    ///            caller does not have enough balance.
    ///         Emits `Transfer(caller, address(0), amount)` followed by
    ///         `Redeemed(caller, amount, sharesToTokensRatio)`.
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
    ///         `SecurityIdentifierUpdated`. Reverts with `InvalidIdentifierType`
    ///         if `identifierType` is the empty string. Standard
    ///         usage is to invoke this through `announce(...)`'s
    ///         `internalCalls`, which brackets the identifier change
    ///         with a matching disclosure atomically (see the
    ///         contract-level "Announcement pairing" notes). Direct
    ///         invocation by a role holder remains permitted for
    ///         emergency override but produces no `Announcement` /
    ///         `EndAnnouncement` bracket.
    ///
    /// @param  identifierType Identifier category (e.g. "ISIN").
    /// @param  value          New value, or empty string to remove.
    function updateSecurityIdentifier(string calldata identifierType, string calldata value) external;
}
