// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IDefaultToken
/// @notice The base Solidity surface every Base-native token (B-20) implements.
///         Variants (Stablecoin, Security, ...) extend this interface; nothing
///         on this surface is variant-specific. A token created at the Default
///         variant address presents exactly this interface.
///
/// @dev    Backward-compatible with ERC-20 at the function-selector level:
///         `transfer`, `transferFrom`, `approve`, `balanceOf`, `allowance`,
///         `totalSupply`, `name`, `symbol`, `decimals` all match ERC-20
///         selectors and event signatures. Memo'd siblings live alongside,
///         and their existence does not change the ERC-20 selectors any
///         wallet or contract already expects.
///
///         **Role model.** Standard OpenZeppelin AccessControl semantics:
///         five named roles (`DEFAULT_ADMIN_ROLE`, `MINT_ROLE`, `BURN_ROLE`,
///         `PAUSE_ROLE`, `UNPAUSE_ROLE`) plus arbitrary user-defined roles.
///         `grantRole`, `revokeRole`, `renounceRole`, and `setRoleAdmin`
///         work uniformly across all roles. The only protocol-level
///         constraint is that the LAST holder of `DEFAULT_ADMIN_ROLE`
///         cannot renounce: the token must always have at least one admin.
///
///         **Pause model.** Pause is granular: `pause(uint256 vectors)`
///         accepts a bitmask indicating which classes of operation to halt
///         (transfer, mint, burn, ...). Multiple `pause` calls are
///         additive. `unpause()` clears all paused vectors at once. See
///         `PauseVectors` for the bit definitions.
///
///         **Capability bits.** Every token's optional features are gated
///         by an immutable `capabilities()` bitfield set at creation.
///         Functions whose capability bit is unset revert with
///         `FeatureDisabled`, regardless of role state. See `Capabilities`.
///
///         **Policy model.** Every transfer, mint, and redeem passes
///         through the token's currently-set policy ID, resolved against
///         the singleton policy registry. Transfer checks consult the
///         policy for `from`, `to`, AND `msg.sender` (the spender, when
///         distinct from `from`). Mint checks consult the policy for the
///         recipient via the mint-recipient slot of a compound policy.
///         Redeem checks consult the policy for `msg.sender` via the
///         redeemer slot of a compound policy: tokens without redemption
///         configure that slot as always-reject, making `redeem` revert
///         for every caller. Burn checks consult only the role of the
///         caller; `BURN_ROLE` plus the caller's own balance are
///         sufficient. `approve` is NOT gated by the policy (only the
///         act of MOVING balance is gated).
///
///         **Permit.** EIP-2612 permit, EOA signatures only. ERC-1271
///         contract signatures are NOT supported on the default surface
///         (smart-contract accounts use call-batching or paymaster flows
///         instead to set allowances). EIP-712 domain is
///         `(chainId, verifyingContract)` only, with `name` and `version`
///         empty. ERC-5267 `eip712Domain()` is exposed for domain
///         introspection by integrators.
interface IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice `account` does not hold `neededRole`. Used for ALL
    ///         role-based access checks: function-level role gates
    ///         (`MINT_ROLE`, `BURN_ROLE`, etc.), `grantRole` /
    ///         `revokeRole` when the caller does not hold the admin role
    ///         for the target role, and `setRoleAdmin` when the caller
    ///         does not hold the current admin role for the target role.
    /// @dev    Matches OZ AccessControl's `AccessControlUnauthorizedAccount`
    ///         error exactly. Since `getRoleAdmin(role)` defaults to
    ///         `DEFAULT_ADMIN_ROLE` for any role that has not had a
    ///         custom admin set, calls like
    ///         `grantRole(SOME_UNREGISTERED_ROLE, alice)` revert with
    ///         `neededRole == DEFAULT_ADMIN_ROLE` rather than a
    ///         "role does not exist" error: every `bytes32` is a valid
    ///         role identifier in this model.
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /// @notice Caller failed a positional authorization check that is NOT
    ///         expressible as "missing role X" (e.g. caller must be the
    ///         specific account whose state is being mutated, in
    ///         contexts where no role applies). Used sparingly; most
    ///         authorization failures revert with
    ///         `AccessControlUnauthorizedAccount`.
    error Unauthorized();

    /// @notice One or more pause vectors covering this operation are
    ///         currently set. `pausedVector` is the specific vector that
    ///         blocked the call.
    error ContractPaused(uint256 pausedVector);

    /// @notice `spender`'s allowance from the relevant token owner is
    ///         less than `needed` for the requested `transferFrom`.
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice `sender`'s balance is less than `needed` for the requested
    ///         transfer, burn, or redeem.
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice The transfer's source address is invalid (typically
    ///         `address(0)`, which cannot hold balance to send from).
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InvalidSender(address sender);

    /// @notice The transfer's destination address is invalid (typically
    ///         `address(0)`; mints and burns use the literal zero
    ///         address as the from/to and are not subject to this check).
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InvalidReceiver(address receiver);

    /// @notice The approval's `owner` address is invalid (typically
    ///         `address(0)`).
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InvalidApprover(address approver);

    /// @notice The approval's `spender` address is invalid (typically
    ///         `address(0)`).
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InvalidSpender(address spender);

    /// @notice An amount argument was zero where a non-zero value is
    ///         required (e.g. `pause(0)`). NOT used for ERC-20 amount
    ///         arguments: per OZ / ERC-6093, ERC-20 functions do not
    ///         validate `amount > 0`.
    error InvalidAmount();

    /// @notice The proposed supply cap is below the current `totalSupply`,
    ///         which would invalidate already-issued supply.
    error InvalidSupplyCap(uint256 currentSupply, uint256 proposedCap);

    /// @notice The mint would push `totalSupply` past the configured cap.
    error SupplyCapExceeded(uint256 cap, uint256 attempted);

    /// @notice The active transfer policy denied the operation. `policyId`
    ///         is the ID currently set as `transferPolicyId`.
    error PolicyForbids(uint64 policyId);

    /// @notice The provided policy ID does not exist in the policy
    ///         registry.
    error PolicyNotFound(uint64 policyId);

    /// @notice An EIP-2612 `permit` was submitted with a `deadline`
    ///         strictly less than the current block timestamp.
    /// @dev    Matches OZ ERC20Permit's `ExpiredSignature` error
    ///         exactly.
    error ExpiredSignature(uint256 deadline);

    /// @notice ECDSA recovery on an EIP-2612 `permit` returned `signer`,
    ///         which does not match the claimed `owner`.
    /// @dev    Matches OZ ERC20Permit's `InvalidSigner` error
    ///         exactly.
    error InvalidSigner(address signer, address owner);

    /// @notice The capability bit for this operation is not set on the
    ///         token. Capability state is immutable; this revert is
    ///         permanent.
    error FeatureDisabled(uint256 capability);

    /// @notice The redemption amount is below the configured
    ///         `minimumRedeemable` threshold.
    error MinimumRedeemableNotMet(uint256 amount, uint256 minimum);

    /// @notice `renounceRole(DEFAULT_ADMIN_ROLE, ...)` was called when the
    ///         caller is the last admin. Tokens MUST always have at least
    ///         one admin; rotate to a new admin first via `grantRole`.
    error LastAdminCannotRenounce();

    /// @notice The `callerConfirmation` argument to `renounceRole` was not
    ///         `msg.sender`. This guard prevents accidental renunciation
    ///         caused by a fat-fingered call to a different account's
    ///         role.
    /// @dev    Matches OZ AccessControl's `AccessControlBadConfirmation`
    ///         error exactly.
    error AccessControlBadConfirmation();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-20 standard transfer event. Emitted on every successful
    ///         transfer (including memo'd variants), mint
    ///         (`from = address(0)`), and burn (`to = address(0)`).
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice ERC-20 standard approval event.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice Emitted by `transferWithMemo`, `transferFromWithMemo`,
    ///         `mintWithMemo`, and `burnWithMemo` immediately AFTER the
    ///         underlying ERC-20 `Transfer` event. The memo carries no
    ///         from/to/amount fields; indexers join it to the preceding
    ///         `Transfer` log via `(transactionHash, logIndex - 1)`.
    /// @dev    Variants may emit this event from additional functions
    ///         (e.g. `redeem` on a Security token); the event signature
    ///         is shared.
    event Memo(bytes32 indexed memo);

    /// @notice Emitted when `account` is granted `role`. `sender` is the
    ///         account that originated the call (the admin for `role`,
    ///         or the same as `account` if the grant happens via factory
    ///         init or other internal path).
    /// @dev    Matches OZ AccessControl's `RoleGranted` event exactly.
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted when `role` is revoked from `account`. `sender`
    ///         is the account that originated the call:
    ///         - if via `revokeRole`, it is the admin role bearer
    ///         - if via `renounceRole`, it is the role bearer (i.e.
    ///           `account`)
    /// @dev    Matches OZ AccessControl's `RoleRevoked` event exactly.
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted when the admin role for `role` is changed via
    ///         `setRoleAdmin`. `DEFAULT_ADMIN_ROLE` is the implicit
    ///         starting admin for all roles, despite this event NOT
    ///         being emitted to signal that initial state.
    /// @dev    Matches OZ AccessControl's `RoleAdminChanged` event
    ///         exactly. Note OZ does NOT include a `sender` parameter
    ///         here; this is intentional alignment.
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /// @notice Emitted by `pause`. `vectors` is the bitmask added to the
    ///         current paused state (the result of `current | vectors`,
    ///         not the argument). `updater` is the caller.
    event Paused(address indexed updater, uint256 vectors);

    /// @notice Emitted by `unpause`. All paused vectors are cleared.
    event Unpaused(address indexed updater);

    /// @notice Emitted by `changeTransferPolicyId`. Includes the prior ID
    ///         for indexer convenience.
    event TransferPolicyUpdated(address indexed updater, uint64 oldPolicyId, uint64 newPolicyId);

    /// @notice Emitted by `setSupplyCap`. Includes the prior cap for
    ///         indexer convenience.
    event SupplyCapUpdated(address indexed updater, uint256 oldSupplyCap, uint256 newSupplyCap);

    /// @notice Emitted by `setContractURI`. Per ERC-7572, this event is
    ///         intentionally parameterless: integrators re-fetch
    ///         `contractURI()` after seeing it.
    event ContractURIUpdated();

    /// @notice Emitted by `setName`. Carries the new name string for
    ///         indexer consumption.
    event NameUpdated(address indexed updater, string newName);

    /// @notice Emitted by `setSymbol`. Carries the new symbol string for
    ///         indexer consumption.
    event SymbolUpdated(address indexed updater, string newSymbol);

    /// @notice Emitted by `redeem` and `redeemWithMemo` (in addition to
    ///         the standard `Transfer(holder, address(0), amount)`).
    ///         Distinguishes user-initiated redemption (which implies an
    ///         off-chain settlement obligation) from plain `burn`, which
    ///         emits the same `Transfer` event but carries no
    ///         off-chain meaning.
    event Redeemed(address indexed holder, uint256 amount);

    /// @notice Emitted by `setMinimumRedeemable`. Includes the prior
    ///         minimum for indexer convenience.
    event MinimumRedeemableUpdated(address indexed updater, uint256 oldMinimum, uint256 newMinimum);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The default top-level admin role, equal to `bytes32(0)` per
    ///         the OpenZeppelin AccessControl convention. The admin
    ///         manages all other roles via `grantRole`, `revokeRole`, and
    ///         `setRoleAdmin`. The admin can also `changeTransferPolicyId`,
    ///         `setSupplyCap`, `setContractURI`, `setName`, and `setSymbol`.
    /// @dev    Unlike earlier drafts, there is NO two-step delay-protected
    ///         transfer for this role. `grantRole(DEFAULT_ADMIN_ROLE, ...)`
    ///         and `revokeRole(DEFAULT_ADMIN_ROLE, ...)` work uniformly.
    ///         The only constraint is that the last admin cannot renounce
    ///         (see `LastAdminCannotRenounce`).
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Required to call `mint` and `mintWithMemo`. Held separately
    ///         from `BURN_ROLE` so issuance and destruction authority can
    ///         be split across teams (e.g. treasury team mints, redemption
    ///         team burns).
    function MINT_ROLE() external view returns (bytes32);

    /// @notice Required to call `burn` and `burnWithMemo`. Note that burn
    ///         operates on the caller's own balance only; there is no
    ///         force-burn function on the Default surface.
    function BURN_ROLE() external view returns (bytes32);

    /// @notice Required to call `pause`. Held separately from
    ///         `UNPAUSE_ROLE` so emergency-stop authority can be delegated
    ///         to a 24/7 ops team without also granting unpause authority.
    function PAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `unpause`. Distinct from `PAUSE_ROLE` so
    ///         resumption requires a deliberate, typically more senior
    ///         action than the pause itself.
    function UNPAUSE_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              CAPABILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The immutable feature bitfield assigned at creation. Each
    ///         bit indicates that the corresponding optional function CAN
    ///         be called on this token. Bits not set here mean the
    ///         corresponding function reverts with `FeatureDisabled`,
    ///         permanently. See `Capabilities` for the bit definitions.
    function capabilities() external view returns (uint256);

    /// @notice Convenience view: `(capabilities() & Capabilities.PAUSABLE) != 0`.
    function isPausable() external view returns (bool);

    /// @notice Convenience view: `(capabilities() & Capabilities.CAP_MUTABLE) != 0`.
    function isCapMutable() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                  ERC-20
    //////////////////////////////////////////////////////////////*/

    /// @notice Token name. Set at creation, mutable via `setName`.
    function name() external view returns (string memory);

    /// @notice Token symbol. Set at creation, mutable via `setSymbol`.
    function symbol() external view returns (string memory);

    /// @notice Number of decimal places. Set at creation, immutable
    ///         thereafter. The factory determines whether `decimals` is
    ///         a per-token parameter or a fixed value (the choice is a
    ///         factory concern, not a token concern).
    function decimals() external view returns (uint8);

    /// @notice Total token supply currently in circulation.
    function totalSupply() external view returns (uint256);

    /// @notice Balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Allowance granted by `owner` to `spender`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Transfers `amount` from `msg.sender` to `to`. Reverts with:
    ///         - `ContractPaused(TRANSFER)` if the `TRANSFER` pause vector
    ///           is set.
    ///         - `PolicyForbids(transferPolicyId)` if the active transfer
    ///           policy denies the transfer.
    ///         - `InsufficientBalance(msg.sender, balance, amount)`
    ///           if the caller does not have enough balance.
    ///         - `InvalidReceiver(to)` if `to == address(0)`.
    /// @dev    Policy check evaluates `msg.sender` (the sender of value)
    ///         and `to` (the recipient). When the token is configured as
    ///         a gas asset, fee debits go through this same path.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` from `from` to `to` using `msg.sender`'s
    ///         allowance. Reverts as `transfer` does, plus:
    ///         - `InsufficientAllowance(msg.sender, allowance, amount)`
    ///           if the caller does not have enough allowance from `from`.
    ///         - `InvalidSender(from)` if `from == address(0)`.
    /// @dev    Policy check evaluates `from` (the sender of value), `to`
    ///         (the recipient), AND `msg.sender` (the spender, when
    ///         distinct from `from`). A sanctioned spender cannot move
    ///         tokens for a non-sanctioned holder.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Sets `spender`'s allowance to `amount`. NOT gated by the
    ///         transfer policy or by pause; only the act of MOVING balance
    ///         is gated. A user on the policy blocklist may still
    ///         `approve` (the approval cannot be acted on by the spender,
    ///         since `transferFrom` would revert).
    /// @dev    Reverts with `InvalidApprover(msg.sender)` if the
    ///         caller is `address(0)` (theoretically unreachable for
    ///         normal callers but enforced for parity with OZ ERC20),
    ///         and `InvalidSpender(spender)` if
    ///         `spender == address(0)`.
    function approve(address spender, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                            METADATA UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the token's `name`. Requires `DEFAULT_ADMIN_ROLE`.
    ///         No length restrictions. Emits `NameUpdated`.
    /// @dev    Several customers (Coinbase Tokenized Equities, Coinbase
    ///         Wrapped Assets) need the ability to update name and symbol
    ///         post-deployment for re-branding or legal-restructuring
    ///         events. There is no capability bit for this; tokens that
    ///         do not want to update their name simply never call this
    ///         function.
    function setName(string calldata newName) external;

    /// @notice Updates the token's `symbol`. Requires `DEFAULT_ADMIN_ROLE`.
    ///         No length restrictions. Emits `SymbolUpdated`.
    function setSymbol(string calldata newSymbol) external;

    /*//////////////////////////////////////////////////////////////
                          MEMO TRANSFER VARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Same as `transfer`, but additionally emits `Memo(memo)`
    ///         immediately after the standard `Transfer` event. The
    ///         standard `Transfer` event is also emitted for ERC-20
    ///         indexer compatibility.
    /// @dev    The memo event carries only the memo. Indexers join it to
    ///         the preceding `Transfer` log via
    ///         `(transactionHash, logIndex - 1)`. Same access control and
    ///         policy checks as `transfer`. A memo of `bytes32(0)` is
    ///         permitted; it indicates "no memo" while still emitting the
    ///         memo event.
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external returns (bool);

    /// @notice Same as `transferFrom`, with a memo. See `transferWithMemo`.
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              MINT / BURN
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amount` to `to`. Requires `MINT_ROLE`. Subject to:
    ///         1. `totalSupply + amount <= supplyCap` (else
    ///            `SupplyCapExceeded`).
    ///         2. The `MINT` pause vector is unset (else
    ///            `ContractPaused(MINT)`).
    ///         3. The active transfer policy authorizes `to` as a mint
    ///            recipient (else `PolicyForbids`).
    /// @dev    There is no `MINTABLE` capability bit. To make a token
    ///         permanently fixed-supply, set `supplyCap == initialSupply`
    ///         at creation with `CAP_MUTABLE` unset; future mint calls
    ///         will revert with `SupplyCapExceeded` because the cap can
    ///         never be raised. To pause minting temporarily, set the
    ///         `MINT` pause vector or revoke `MINT_ROLE`.
    ///
    ///         Per-minter rate limiting is NOT enshrined at any level
    ///         (Default or variant). Minter quotas live in EVM
    ///         periphery contracts: a controller / wrapper that holds
    ///         `MINT_ROLE` and enforces per-caller quotas before
    ///         invoking `mint` on the precompile. Bridge's
    ///         `TIP20Controller` and CDP Custom Stablecoin's mint flow
    ///         are both expressible this way.
    ///         Emits `Transfer(address(0), to, amount)`.
    function mint(address to, uint256 amount) external;

    /// @notice Same as `mint`, with a memo. Emits `Memo(memo)` immediately
    ///         after the standard `Transfer` event.
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external;

    /// @notice Burns `amount` from the caller's own balance. Requires
    ///         `BURN_ROLE`. Subject to the `BURN` pause vector being unset
    ///         (else `ContractPaused(BURN)`). NOT subject to the transfer
    ///         policy: burn destroys the caller's own supply with no
    ///         recipient. Reverts with
    ///         `InsufficientBalance(caller, balance, amount)` if the
    ///         caller does not have enough balance.
    /// @dev    There is no force-burn function on the Default surface.
    ///         Sanctions seizure flows live in token variants (e.g.
    ///         Security via `adminBurn`) or in periphery contracts.
    ///         Emits `Transfer(caller, address(0), amount)`.
    function burn(uint256 amount) external;

    /// @notice Same as `burn`, with a memo. Emits `Memo(memo)` immediately
    ///         after the standard `Transfer` event.
    function burnWithMemo(uint256 amount, bytes32 memo) external;

    /*//////////////////////////////////////////////////////////////
                                 REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @notice Destroys `amount` of the caller's balance, signaling an
    ///         off-chain redemption claim against the issuer. Subject to:
    ///         1. `amount >= minimumRedeemable()` (else
    ///            `MinimumRedeemableNotMet(amount, minimum)`).
    ///         2. `amount <= balanceOf(msg.sender)` (else
    ///            `InsufficientBalance(msg.sender, balance, amount)`).
    ///         3. The `REDEEM` pause vector is unset (else
    ///            `ContractPaused(REDEEM)`).
    ///         4. The active transfer policy authorizes `msg.sender` as
    ///            a redeemer (else `PolicyForbids(transferPolicyId)`).
    /// @dev    No role is required: redemption is a user-initiated
    ///         operation on the caller's own balance, gated entirely by
    ///         the policy's redeemer slot.
    ///
    ///         Tokens that do not offer redemption configure their
    ///         transfer policy with the redeemer slot pointed at policy
    ///         ID `0` (always-reject); calls to `redeem` then revert
    ///         with `PolicyForbids` for every caller. The function is
    ///         present on every Default token but its availability is
    ///         policy-driven.
    ///
    ///         Distinct from `burn` (which requires `BURN_ROLE` and
    ///         carries no off-chain settlement implication). Both emit
    ///         `Transfer(holder, address(0), amount)`; `redeem`
    ///         additionally emits `Redeemed(holder, amount)` so indexers
    ///         can distinguish.
    function redeem(uint256 amount) external;

    /// @notice Same as `redeem`, with a memo. Emits `Memo(memo)`
    ///         immediately after the standard `Transfer` event (and
    ///         after `Redeemed`).
    function redeemWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice The minimum amount that may be redeemed in a single call
    ///         to `redeem` / `redeemWithMemo`. Defaults to 0 (no
    ///         minimum) at creation.
    function minimumRedeemable() external view returns (uint256);

    /// @notice Sets a new minimum redeemable amount. Requires
    ///         `DEFAULT_ADMIN_ROLE`. May be set to 0 to disable the
    ///         minimum entirely. Takes effect immediately for the next
    ///         redemption.
    function setMinimumRedeemable(uint256 newMinimum) external;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns whether `account` is a member of `role`. `role` may
    ///         be any `bytes32` value; user-defined roles are supported and
    ///         have no built-in effect on the token's own functions but
    ///         may be consumed by external contracts.
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @notice Returns the role required to grant or revoke `role`.
    ///         Defaults to `DEFAULT_ADMIN_ROLE` if not explicitly set via
    ///         `setRoleAdmin`.
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /// @notice Grants `role` to `account`. Caller MUST hold the admin
    ///         role for `role` (see `getRoleAdmin`).
    function grantRole(bytes32 role, address account) external;

    /// @notice Revokes `role` from `account`. Caller MUST hold the admin
    ///         role for `role`.
    function revokeRole(bytes32 role, address account) external;

    /// @notice Caller renounces `role` for themselves. Always permitted
    ///         (no admin authorization needed).
    /// @dev    `callerConfirmation` MUST equal `msg.sender`; otherwise
    ///         reverts with `AccessControlBadConfirmation`. This guard
    ///         prevents a fat-fingered call from accidentally renouncing
    ///         for a different account.
    ///
    ///         Reverts with `LastAdminCannotRenounce` if `role` is
    ///         `DEFAULT_ADMIN_ROLE` and `msg.sender` is the only current
    ///         admin: the token must always have at least one admin.
    ///         Rotate to a new admin first via `grantRole`, then
    ///         renounce.
    function renounceRole(bytes32 role, address callerConfirmation) external;

    /// @notice Sets the admin role for `role`. Caller MUST hold the
    ///         current admin role for `role`. Useful for delegating role
    ///         management to a different role hierarchy.
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external;

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice The current paused-vector bitmask. A bit set in the result
    ///         means the corresponding class of operation (per
    ///         `PauseVectors`) is currently halted. Returns 0 when no
    ///         vectors are paused. Always returns 0 if the token's
    ///         `PAUSABLE` capability is unset.
    function paused() external view returns (uint256);

    /// @notice Convenience view: returns whether `vector` is set in the
    ///         current paused bitmask. Equivalent to
    ///         `(paused() & vector) != 0`.
    function isPaused(uint256 vector) external view returns (bool);

    /// @notice Pauses the operations indicated by `vectors`. Multiple
    ///         calls are additive: the new paused state is
    ///         `currentPaused | vectors`. Requires `PAUSABLE` capability
    ///         and `PAUSE_ROLE`. Reverts with `InvalidAmount` if
    ///         `vectors == 0`.
    /// @dev    See `PauseVectors` for the bit definitions. Pausing a
    ///         vector that is already set is a no-op for the bitmask but
    ///         still emits `Paused(updater, vectors)` with the argument
    ///         as supplied (for indexer trace).
    function pause(uint256 vectors) external;

    /// @notice Unpauses ALL currently-paused vectors. Requires `PAUSABLE`
    ///         capability and `UNPAUSE_ROLE`. The Default surface does
    ///         not support unpausing a subset of vectors; admin must
    ///         unpause everything and re-pause the still-blocked vectors
    ///         in a follow-up call if granular resumption is desired.
    /// @dev    No-op if no vectors are currently paused; still emits
    ///         `Unpaused(updater)`.
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                                 POLICY
    //////////////////////////////////////////////////////////////*/

    /// @notice The policy ID currently gating this token's transfers and
    ///         mints. Resolved against the singleton policy registry
    ///         precompile. ID `0` always rejects (functional soft-pause
    ///         via policy); ID `1` always allows.
    function transferPolicyId() external view returns (uint64);

    /// @notice Sets a new transfer policy. Requires `DEFAULT_ADMIN_ROLE`.
    ///         The policy MUST exist in the registry (or be one of the
    ///         built-in IDs `0` or `1`); otherwise reverts with
    ///         `PolicyNotFound`. Takes effect immediately for the next
    ///         transfer or mint.
    function changeTransferPolicyId(uint64 newPolicyId) external;

    /*//////////////////////////////////////////////////////////////
                              SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    /// @notice The maximum total supply enforced on `mint`. A value of
    ///         `type(uint256).max` indicates no cap (the default for
    ///         tokens that do not specify a cap at creation).
    function supplyCap() external view returns (uint256);

    /// @notice Sets a new supply cap. Requires `CAP_MUTABLE` capability
    ///         and `DEFAULT_ADMIN_ROLE`. Reverts with `InvalidSupplyCap`
    ///         if the new cap is below the current `totalSupply` (we
    ///         never invalidate already-issued supply). The cap may be
    ///         raised or lowered freely otherwise. Emits
    ///         `SupplyCapUpdated`.
    function setSupplyCap(uint256 newSupplyCap) external;

    /*//////////////////////////////////////////////////////////////
                       PERMIT (EIP-2612 + ERC-5267)
    //////////////////////////////////////////////////////////////*/

    /// @notice The current EIP-712 domain separator for this token.
    ///         Computed dynamically each call so it remains correct after
    ///         a chain fork that changes `block.chainid`.
    /// @dev    Domain content: `chainId` and `verifyingContract` only.
    ///         `name` and `version` are intentionally empty strings.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The current permit nonce for `owner`. Incremented by
    ///         exactly 1 on each successful `permit`.
    function nonces(address owner) external view returns (uint256);

    /// @notice EIP-2612 canonical permit. Recovers `owner` via ECDSA from
    ///         `(v, r, s)`. EOA signatures only; ERC-1271 contract
    ///         signatures are NOT supported on the Default surface.
    ///         Reverts with `ExpiredSignature(deadline)` if
    ///         `block.timestamp > deadline`, or
    ///         `InvalidSigner(recovered, owner)` if recovery does
    ///         not yield `owner`.
    /// @dev    Smart-contract accounts that need permit-style flows should
    ///         use call-batching (e.g. the EIP-7702 path) or paymaster-
    ///         based gasless flows; we deliberately do not enshrine
    ///         ERC-1271 dispatch here. Permit2 remains usable as a
    ///         periphery alternative.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /// @notice ERC-5267 EIP-712 domain introspection. Returns the parts
    ///         of the EIP-712 domain populated for this token.
    /// @dev    For Default tokens, `fields` is `0x0c` (bits 2 and 3 set,
    ///         indicating `chainId` and `verifyingContract` are populated).
    ///         `name`, `version`, and `salt` are empty / zero.
    ///         `extensions` is empty.
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    /*//////////////////////////////////////////////////////////////
                          CONTRACT URI (ERC-7572)
    //////////////////////////////////////////////////////////////*/

    /// @notice An off-chain URI pointing at contract-level metadata for
    ///         this token, per ERC-7572.
    function contractURI() external view returns (string memory);

    /// @notice Updates `contractURI`. Requires `DEFAULT_ADMIN_ROLE`. Emits
    ///         the parameterless `ContractURIUpdated` event per ERC-7572;
    ///         integrators re-fetch `contractURI()` after observing it.
    function setContractURI(string calldata newURI) external;
}
