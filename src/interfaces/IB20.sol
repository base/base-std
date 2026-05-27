// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IB20
/// @notice The base Solidity surface every Base-native token (B-20) implements.
///         Variants (Stablecoin, Security, ...) extend this interface; nothing
///         on this surface is variant-specific.
///
/// @dev    Backward-compatible with ERC-20 at the function-selector level:
///         `transfer`, `transferFrom`, `approve`, `balanceOf`, `allowance`,
///         `totalSupply`, `name`, `symbol`, `decimals` all match ERC-20
///         selectors and event signatures. Memo'd siblings live alongside,
///         and their existence does not change the ERC-20 selectors any
///         wallet or contract already expects.
///
///         **Role model.** Standard OpenZeppelin AccessControl semantics:
///         seven named roles (`DEFAULT_ADMIN_ROLE`, `MINT_ROLE`, `BURN_ROLE`,
///         `BURN_BLOCKED_ROLE`, `PAUSE_ROLE`, `UNPAUSE_ROLE`, `METADATA_ROLE`)
///         plus arbitrary user-defined roles. `grantRole`, `revokeRole`, `renounceRole`, and
///         `setRoleAdmin` work uniformly across all roles, with one
///         protocol-level constraint: the LAST holder of
///         `DEFAULT_ADMIN_ROLE` cannot renounce via `renounceRole` (this
///         guards against accidentally bricking the token's admin
///         surface). Tokens that DO want to permanently shed admin
///         control (e.g. memecoins finalizing a fair launch, immutable
///         tokens locking in their configuration) use the dedicated
///         `renounceLastAdmin()` function, whose distinct name and
///         existence is the explicit intent signal. After
///         `renounceLastAdmin()` the token has zero admins forever: no
///         further `grantRole(DEFAULT_ADMIN_ROLE, ...)`, no policy
///         updates, no supply-cap changes, no name/symbol changes, no
///         further admin operations of any kind.
///
///         **Pause model.** Pause is granular: `pause(PausableFeature[])`
///         halts a set of operation classes (transfer, mint, burn, ...)
///         and `unpause(PausableFeature[])` resumes a (possibly
///         different) subset. Both are additive against the
///         currently-paused set, so callers can pause incrementally and
///         resume a single class without disturbing the others. The
///         on-chain storage layout (a bitmask) is an implementation
///         detail; the public surface speaks only in `PausableFeature`
///         values.
///
///         **Policy model.** Each supported `bytes32 policyScope` resolves
///         to a dedicated storage slot on the token. The policy-type
///         identifier is the `keccak256` hash of its name. Four standard
///         types are exposed as constants on this base surface:
///         - `TRANSFER_SENDER_POLICY`   — checked against `from` on every transfer
///         - `TRANSFER_RECEIVER_POLICY` — checked against `to`   on every transfer
///         - `TRANSFER_EXECUTOR_POLICY` — checked against `msg.sender` on `transferFrom`
///                                  (when distinct from `from`)
///         - `MINT_RECEIVER_POLICY`     — checked against `to`   on every mint
///         Variants extend this set by adding their own dedicated slots
///         (e.g. `IB20Asset` adds `REDEEM_SENDER_POLICY` for its `redeem`
///         path, stored in the variant's own namespaced storage). There
///         is no generic catch-all mapping: every `policyScope` either
///         resolves to a real slot or doesn't exist at all. Both reads
///         (`policyId`) and writes (`updatePolicy`) for a `policyScope`
///         not supported by the token (or its variant) revert
///         `UnsupportedPolicyType` — an unsupported `policyScope` is
///         nonsense the token can't parse, so the registry never gets
///         consulted with it. (Reads stay strict, not silent-zero,
///         because a typo'd query returning `0` would masquerade as
///         "no restriction" instead of surfacing the bug.)
///
///         Each policy slot defaults to built-in ID `0` (always-allow) so
///         newly created tokens are unrestricted until the admin
///         configures their compliance regime. ID `type(uint64).max`
///         (always-reject) is the explicit hard-deny for a given role
///         (e.g. disabling redemption on a non-redeemable token).
///
///         Asymmetric per-role configuration is expressed by pointing
///         different slots at different policies — for example, a
///         sanctions BLOCKLIST on `TRANSFER_SENDER_POLICY` and an unrestricted
///         always-allow on `TRANSFER_RECEIVER_POLICY`. The registry stays flat;
///         all composition happens at the token layer. `approve` is NOT
///         gated by any policy (only the act of MOVING balance is gated).
///
///         **Permit.** EIP-2612 permit, EOA signatures only. ERC-1271
///         contract signatures are NOT supported on the default surface
///         (smart-contract accounts use call-batching or paymaster flows
///         instead to set allowances). The EIP-712 domain binds
///         `(name, version, chainId, verifyingContract)` — the
///         canonical EIP-2612 shape, so off-the-shelf permit helpers
///         (viem, ethers, wagmi, OpenZeppelin) and wallet UIs
///         (MetaMask in particular, which renders `domain.name`
///         prominently in the signing prompt) work without
///         per-token customization. `name` is the live token `name()`,
///         re-hashed into the domain on each call so a successful
///         `updateName(...)` invalidates outstanding signatures and
///         emits ERC-5267 `EIP712DomainChanged()` to signal the
///         change. `version` is the constant string `"1"` and never
///         changes; bumping it would require a new contract anyway.
///         `salt` is unused (empty). ERC-5267 `eip712Domain()` is
///         exposed for domain introspection by integrators that
///         prefer to read the domain dynamically rather than
///         reconstruct it from `name()` + the conventional shape.
interface IB20 {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Pausable operation classes. Passed in arrays to `pause`
    ///         and `unpause`, returned by `pausedFeatures`, and used by
    ///         `isPaused` and the `ContractPaused` revert. Append-only
    ///         across protocol versions; existing values are stable.
    enum PausableFeature {
        TRANSFER,
        MINT,
        BURN,
        REDEEM
    }

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
    ///         error exactly.
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /// @notice Caller failed a positional authorization check that is NOT
    ///         expressible as "missing role X" (e.g. caller must be the
    ///         specific account whose state is being mutated, in
    ///         contexts where no role applies). Used sparingly; most
    ///         authorization failures revert with
    ///         `AccessControlUnauthorizedAccount`.
    error Unauthorized();

    /// @notice The `PausableFeature` covering this operation is
    ///         currently paused.
    error ContractPaused(PausableFeature feature);

    /// @notice `spender`'s allowance from the relevant token owner is
    ///         less than `needed` for the requested `transferFrom`.
    /// @dev    Matches OZ ERC20 / ERC-6093 exactly.
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice `sender`'s balance is less than `needed` for the requested
    ///         transfer or burn.
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
    ///         required. NOT used for ERC-20 amount arguments: per OZ /
    ///         ERC-6093, ERC-20 functions do not validate `amount > 0`.
    error InvalidAmount();

    /// @notice An empty array was passed to a function that requires at
    ///         least one element (e.g. `pause([])`, `unpause([])`).
    error EmptyFeatureSet();

    /// @notice The proposed supply cap is below the current `totalSupply`,
    ///         which would invalidate already-issued supply.
    error InvalidSupplyCap(uint256 currentSupply, uint256 proposedCap);

    /// @notice The mint would push `totalSupply` past the configured cap.
    error SupplyCapExceeded(uint256 cap, uint256 attempted);

    /// @notice A policy slot denied the operation. `policyScope` identifies
    ///         which slot (e.g. `TRANSFER_SENDER_POLICY`, `MINT_RECEIVER_POLICY`) and
    ///         `policyId` is the ID currently set in that slot.
    error PolicyForbids(bytes32 policyScope, uint64 policyId);

    /// @notice The provided policy ID does not exist in the policy
    ///         registry.
    error PolicyNotFound(uint64 policyId);

    /// @notice `policyId` or `updatePolicy` was called with a
    ///         `policyScope` that this token (and its variant, if any)
    ///         does not recognize. Each token implementation defines a
    ///         fixed set of supported policy types; both reads and
    ///         writes for anything outside that set revert here so a
    ///         typo'd query can never be silently interpreted as
    ///         "no restriction", and an admin can never assign a policy
    ///         to a slot that doesn't exist.
    error UnsupportedPolicyType(bytes32 policyScope);

    /// @notice `burnBlocked` was called against a `from` address that is
    ///         currently authorized under the active `TRANSFER_SENDER_POLICY`
    ///         policy. `burnBlocked` exists specifically to seize supply
    ///         from policy-blocked addresses; calling it against a
    ///         non-blocked address is rejected by design.
    error AccountNotBlocked(address account);

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

    /// @notice `renounceRole(DEFAULT_ADMIN_ROLE, ...)` was called when the
    ///         caller is the last admin. `renounceRole` is the routine
    ///         "give up MY hold on this role" path and guards against
    ///         accidentally leaving the token with zero admins; callers
    ///         that intentionally want a permanently adminless token must
    ///         use the dedicated `renounceLastAdmin()` function instead.
    error LastAdminCannotRenounce();

    /// @notice `renounceLastAdmin()` was called by an account that is not
    ///         the sole remaining holder of `DEFAULT_ADMIN_ROLE`. The
    ///         function exists exclusively to transition the token from
    ///         single-admin to zero-admin atomically; revoking other
    ///         admins to reach single-admin state first is the caller's
    ///         responsibility.
    error NotSoleAdmin();

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
    ///         (`from = address(0)`), and burn (`to = address(0)`,
    ///         including `burnBlocked` and `redeem`).
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice ERC-20 standard approval event.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice Emitted by `transferWithMemo`, `transferFromWithMemo`,
    ///         `mintWithMemo`, and `burnWithMemo` immediately AFTER the
    ///         underlying ERC-20 `Transfer` event. `caller` is the
    ///         `msg.sender` of the memo'd call (the spender on
    ///         `transferFromWithMemo`, the holder on the others).
    ///         The memo carries no from/to/amount fields; indexers join
    ///         it to the preceding `Transfer` log via
    ///         `(transactionHash, logIndex - 1)`, and may additionally
    ///         filter on `caller` for per-account memo streams.
    /// @dev    Variants may emit this event from additional functions
    ///         (e.g. `redeem` on a Security token); the event signature
    ///         is shared.
    event Memo(address indexed caller, bytes32 indexed memo);

    /// @notice Emitted by `burnBlocked` in addition to the standard
    ///         `Transfer(from, address(0), amount)`. Distinguishes
    ///         compliance-driven seizure (which destroys balance belonging
    ///         to a third party) from `burn` (which destroys the caller's
    ///         own balance).
    event BurnedBlocked(address indexed caller, address indexed from, uint256 amount);

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
    ///         `setRoleAdmin`. Both the function and event adopt OZ
    ///         AccessControl naming (`setRoleAdmin` + `RoleAdminChanged`)
    ///         rather than this interface's `update*` / `*Updated`
    ///         convention, so OZ-aware tooling (Etherscan, Safe,
    ///         indexers, audit checklists) continues to recognize both
    ///         the role-admin mutator and its log without a separate
    ///         handler.
    /// @dev    Matches OZ AccessControl's `RoleAdminChanged` event exactly.
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /// @notice Emitted by `renounceLastAdmin` in addition to the
    ///         standard `RoleRevoked(DEFAULT_ADMIN_ROLE, previousAdmin,
    ///         previousAdmin)` event. Signals the irreversible
    ///         transition of the token to a permanently adminless
    ///         state: no `grantRole`, `revokeRole`, `setRoleAdmin`,
    ///         `updatePolicy`, or `updateSupplyCap` call can ever
    ///         succeed again. Existing role holders (`MINT_ROLE`,
    ///         `BURN_ROLE`, `METADATA_ROLE`, etc.) retain their
    ///         abilities, but no new grants are possible.
    ///         Indexers should treat this event as a one-way state
    ///         transition.
    event LastAdminRenounced(address indexed previousAdmin);

    /// @notice Emitted by `pause`. `features` is the argument to the
    ///         call (not the resulting paused state). `updater` is the
    ///         caller.
    event Paused(address indexed updater, PausableFeature[] features);

    /// @notice Emitted by `unpause`. `features` is the argument to the
    ///         call (not the resulting paused state). `updater` is the
    ///         caller.
    event Unpaused(address indexed updater, PausableFeature[] features);

    /// @notice Emitted by `updatePolicy` when a token's policy slot is
    ///         changed. `policyScope` is one of the standard policy-type
    ///         identifiers (e.g. `TRANSFER_SENDER_POLICY()`); `oldPolicyId` and
    ///         `newPolicyId` are the prior and current registry IDs for
    ///         that slot. Initial slot assignment at creation is also
    ///         emitted via `PolicyUpdated` with `oldPolicyId == 0`.
    event PolicyUpdated(bytes32 indexed policyScope, uint64 oldPolicyId, uint64 newPolicyId);

    /// @notice Emitted by `updateSupplyCap`. Includes the prior cap for
    ///         indexer convenience.
    event SupplyCapUpdated(address indexed updater, uint256 oldSupplyCap, uint256 newSupplyCap);

    /// @notice Emitted by `updateContractURI`. Per ERC-7572, this event is
    ///         intentionally parameterless: integrators re-fetch
    ///         `contractURI()` after seeing it.
    event ContractURIUpdated();

    /// @notice Emitted by `updateName`. Carries the new name string for
    ///         indexer consumption.
    event NameUpdated(address indexed updater, string newName);

    /// @notice Emitted by `updateSymbol`. Carries the new symbol string for
    ///         indexer consumption.
    event SymbolUpdated(address indexed updater, string newSymbol);

    /// @notice ERC-5267 domain-change signal. Emitted whenever a
    ///         field that participates in this token's EIP-712
    ///         domain changes value. On this surface the only such
    ///         field is `name`, so this event is emitted exactly
    ///         once per successful `updateName(...)` call,
    ///         immediately after the inherited `NameUpdated` event.
    ///         The event signature is parameterless per ERC-5267:
    ///         off-chain integrators that cache `DOMAIN_SEPARATOR()`
    ///         or `eip712Domain()` re-fetch after observing it.
    ///         `updateSymbol(...)` does NOT emit this event; `symbol`
    ///         is not in the EIP-712 domain.
    event EIP712DomainChanged();

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The default top-level admin role, equal to `bytes32(0)` per
    ///         the OpenZeppelin AccessControl convention. The admin
    ///         manages all other roles via `grantRole`, `revokeRole`, and
    ///         `setRoleAdmin`. The admin can also `updatePolicy` and
    ///         `updateSupplyCap`. Name, symbol, and `contractURI` updates
    ///         are gated by `METADATA_ROLE`, not by this role.
    /// @dev    There is NO two-step delay-protected transfer for this
    ///         role. `grantRole(DEFAULT_ADMIN_ROLE, ...)` and
    ///         `revokeRole(DEFAULT_ADMIN_ROLE, ...)` work uniformly.
    ///         The only constraint is that the last admin cannot renounce
    ///         (see `LastAdminCannotRenounce`).
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Required to call `mint` and `mintWithMemo`. Held separately
    ///         from `BURN_ROLE` and `BURN_BLOCKED_ROLE` so issuance and
    ///         destruction authority can be split across teams.
    function MINT_ROLE() external view returns (bytes32);

    /// @notice Required to call `burn` and `burnWithMemo`. Note that
    ///         `burn` operates on the caller's own balance only; to
    ///         destroy supply held by a third party (e.g. for sanctions
    ///         seizure), see `BURN_BLOCKED_ROLE` and `burnBlocked`.
    function BURN_ROLE() external view returns (bytes32);

    /// @notice Required to call `burnBlocked`. Held separately from
    ///         `BURN_ROLE` so the authority to destroy a third party's
    ///         balance (gated on that party being unauthorized under the
    ///         active `TRANSFER_SENDER_POLICY` policy) can be granted only to a
    ///         compliance role, not to general burn operators.
    function BURN_BLOCKED_ROLE() external view returns (bytes32);

    /// @notice Required to call `pause`. Held separately from
    ///         `UNPAUSE_ROLE` so emergency-stop authority can be delegated
    ///         to a 24/7 ops team without also granting unpause authority.
    function PAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `unpause`. Distinct from `PAUSE_ROLE` so
    ///         resumption requires a deliberate, typically more senior
    ///         action than the pause itself.
    function UNPAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `updateName`, `updateSymbol`, and
    ///         `updateContractURI`. Held separately from
    ///         `DEFAULT_ADMIN_ROLE` so the authority to re-brand or
    ///         legally-restructure the token can be delegated to a
    ///         metadata operator (e.g. corporate-actions desk for
    ///         asset tokens) without granting the broader admin
    ///         powers (role grants, policy changes, supply-cap changes,
    ///         etc.).
    function METADATA_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          POLICY TYPE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The policy slot consulted against `from` on every transfer
    ///         (including the `from` side of `transferFrom`). Identifier
    ///         is `keccak256("TRANSFER_SENDER_POLICY")`.
    function TRANSFER_SENDER_POLICY() external view returns (bytes32);

    /// @notice The policy slot consulted against `to` on every transfer.
    ///         Identifier is `keccak256("TRANSFER_RECEIVER_POLICY")`.
    function TRANSFER_RECEIVER_POLICY() external view returns (bytes32);

    /// @notice The policy slot consulted against `msg.sender` on
    ///         `transferFrom` (the spender, when distinct from `from`).
    ///         Not consulted on `transfer` (where `msg.sender == from`).
    ///         Identifier is `keccak256("TRANSFER_EXECUTOR_POLICY")`.
    function TRANSFER_EXECUTOR_POLICY() external view returns (bytes32);

    /// @notice The policy slot consulted against `to` on every mint.
    ///         Identifier is `keccak256("MINT_RECEIVER_POLICY")`.
    function MINT_RECEIVER_POLICY() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                  ERC-20
    //////////////////////////////////////////////////////////////*/

    /// @notice Token name. Set at creation, mutable via `updateName`.
    function name() external view returns (string memory);

    /// @notice Token symbol. Set at creation, mutable via `updateSymbol`.
    function symbol() external view returns (string memory);

    /// @notice Number of decimal places. Immutable per token variant.
    /// @dev    Current variant defaults are fixed by the factory:
    ///         Default = 18, Stablecoin = 6, Security = 6.
    function decimals() external view returns (uint8);

    /// @notice Total token supply currently in circulation.
    function totalSupply() external view returns (uint256);

    /// @notice Balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Allowance granted by `owner` to `spender`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Transfers `amount` from `msg.sender` to `to`. Reverts with:
    ///         - `ContractPaused(TRANSFER)` if `TRANSFER` is paused.
    ///         - `PolicyForbids(TRANSFER_SENDER_POLICY,   policyId)` if `msg.sender`
    ///           is not authorized under the active `TRANSFER_SENDER_POLICY` policy.
    ///         - `PolicyForbids(TRANSFER_RECEIVER_POLICY, policyId)` if `to` is not
    ///           authorized under the active `TRANSFER_RECEIVER_POLICY` policy.
    ///         - `InsufficientBalance(msg.sender, balance, amount)` if the
    ///           caller does not have enough balance.
    ///         - `InvalidReceiver(to)` if `to == address(0)`.
    /// @dev    Does NOT consult the `TRANSFER_EXECUTOR_POLICY` policy: on direct
    ///         `transfer` the executor IS the sender, and the sender
    ///         check already covers that address. When the token is
    ///         configured as a gas asset, fee debits go through this
    ///         same path.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` from `from` to `to` using `msg.sender`'s
    ///         allowance. Reverts as `transfer` does, plus:
    ///         - `InsufficientAllowance(msg.sender, allowance, amount)`
    ///           if the caller does not have enough allowance from `from`.
    ///         - `InvalidSender(from)` if `from == address(0)`.
    ///         - `PolicyForbids(TRANSFER_EXECUTOR_POLICY, policyId)` if
    ///           `msg.sender != from` and `msg.sender` is not authorized
    ///           under the active `TRANSFER_EXECUTOR_POLICY` policy.
    /// @dev    The sender-side check is performed against `from` (the
    ///         party whose balance moves), the receiver check against
    ///         `to`, and the executor check against `msg.sender` only
    ///         when distinct from `from`. A sanctioned spender cannot
    ///         move tokens for a non-sanctioned holder.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Sets `spender`'s allowance to `amount`. NOT gated by any
    ///         policy or by pause; only the act of MOVING balance is gated.
    /// @dev    Reverts with `InvalidApprover(msg.sender)` if the
    ///         caller is `address(0)` (theoretically unreachable for
    ///         normal callers but enforced for parity with OZ ERC20),
    ///         and `InvalidSpender(spender)` if
    ///         `spender == address(0)`.
    function approve(address spender, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                            METADATA UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the token's `name`. Requires `METADATA_ROLE`.
    ///         No length restrictions. Emits `NameUpdated` followed by
    ///         the ERC-5267 `EIP712DomainChanged()` event (in that
    ///         order).
    /// @dev    Several customers (Coinbase Tokenized Equities, Coinbase
    ///         Wrapped Assets) need the ability to update name and symbol
    ///         post-deployment for re-branding or legal-restructuring
    ///         events. Tokens that do not want to update their name
    ///         simply never grant `METADATA_ROLE`.
    ///
    ///         Because `name` is bound into the EIP-712 domain (see
    ///         the contract-level "Permit" notes), a successful
    ///         `updateName(...)` invalidates outstanding off-chain
    ///         `permit` signatures issued under the previous name —
    ///         the recovered signer no longer matches the new
    ///         domain separator.
    function updateName(string calldata newName) external;

    /// @notice Updates the token's `symbol`. Requires `METADATA_ROLE`.
    ///         No length restrictions. Emits `SymbolUpdated`.
    function updateSymbol(string calldata newSymbol) external;

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
    ///         2. `MINT` is not paused (else `ContractPaused(MINT)`).
    ///         3. `to` is authorized under the active `MINT_RECEIVER_POLICY`
    ///            policy (else `PolicyForbids(MINT_RECEIVER_POLICY, policyId)`).
    /// @dev    Per-minter rate limiting is NOT enshrined at any level
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
    ///         `BURN_ROLE`. Subject to `BURN` not being paused (else
    ///         `ContractPaused(BURN)`). NOT subject to any policy:
    ///         burn destroys the caller's own supply with no recipient.
    ///         Reverts with `InsufficientBalance(caller, balance, amount)`
    ///         if the caller does not have enough balance.
    /// @dev    To destroy balance held by a third party (compliance
    ///         seizure from a policy-blocked address), use `burnBlocked`.
    ///         Emits `Transfer(caller, address(0), amount)`.
    function burn(uint256 amount) external;

    /// @notice Same as `burn`, with a memo. Emits `Memo(memo)` immediately
    ///         after the standard `Transfer` event.
    function burnWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice Destroys `amount` of `from`'s balance. Requires
    ///         `BURN_BLOCKED_ROLE`. Subject to:
    ///         1. `BURN` is not paused (else `ContractPaused(BURN)`).
    ///         2. `from` is NOT authorized under the active
    ///            `TRANSFER_SENDER_POLICY` policy (else `AccountNotBlocked(from)`).
    ///            `burnBlocked` exists for seizure of policy-blocked
    ///            balance; calling it against an authorized address is
    ///            rejected by design.
    ///         3. `amount <= balanceOf(from)` (else
    ///            `InsufficientBalance(from, balance, amount)`).
    /// @dev    Designed for sanctions-seizure flows where compliance
    ///         requires destruction of balance held by a blocked
    ///         address. Tokens that follow a "freeze, never seize"
    ///         philosophy (e.g. CDP Custom Stablecoin) simply never
    ///         grant `BURN_BLOCKED_ROLE`.
    ///         Emits `Transfer(from, address(0), amount)` and
    ///         `BurnedBlocked(caller, from, amount)`.
    function burnBlocked(address from, uint256 amount) external;

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
    ///         (no admin authorization needed), EXCEPT that
    ///         `renounceRole(DEFAULT_ADMIN_ROLE, msg.sender)` reverts
    ///         with `LastAdminCannotRenounce` when the caller is the
    ///         sole remaining admin. Callers that intentionally want to
    ///         transition the token to a permanently adminless state
    ///         must use `renounceLastAdmin()` instead; the dedicated
    ///         function name is the explicit intent signal that
    ///         distinguishes "I'm giving up my hold on this role" from
    ///         "the token should have zero admins forever."
    /// @dev    `callerConfirmation` MUST equal `msg.sender`; otherwise
    ///         reverts with `AccessControlBadConfirmation`. This guard
    ///         prevents a fat-fingered call from accidentally renouncing
    ///         for a different account.
    function renounceRole(bytes32 role, address callerConfirmation) external;

    /// @notice Permanently transitions the token to a zero-admin state.
    ///         Revokes `DEFAULT_ADMIN_ROLE` from `msg.sender` and emits
    ///         `LastAdminRenounced(msg.sender)` (in addition to the
    ///         standard `RoleRevoked(DEFAULT_ADMIN_ROLE, msg.sender,
    ///         msg.sender)`). After this call, the token has no admin
    ///         and no holder of `DEFAULT_ADMIN_ROLE` can ever be
    ///         reinstated: `grantRole(DEFAULT_ADMIN_ROLE, ...)` would
    ///         require an admin caller and there is none. All
    ///         admin-gated operations (`updatePolicy`, `updateSupplyCap`,
    ///         and any `grantRole` / `revokeRole` / `setRoleAdmin` for
    ///         other roles) become permanently uncallable. Operations
    ///         gated by other roles (`updateName` / `updateSymbol` /
    ///         `updateContractURI` via `METADATA_ROLE`, `mint` via
    ///         `MINT_ROLE`, etc.) remain callable by their existing
    ///         role holders, but no new grants for those roles are
    ///         possible.
    /// @dev    Caller MUST be the sole remaining holder of
    ///         `DEFAULT_ADMIN_ROLE`; otherwise reverts with
    ///         `NotSoleAdmin` (when there are additional admins) or
    ///         `AccessControlUnauthorizedAccount` (when `msg.sender`
    ///         holds no admin role at all). To reach the single-admin
    ///         state from a multi-admin starting point, the existing
    ///         admin(s) must revoke or renounce other admins first via
    ///         `revokeRole` / `renounceRole`, leaving exactly one.
    ///
    ///         No `callerConfirmation` argument: the dedicated function
    ///         name is the intent signal. This mirrors the
    ///         `renounceAdmin` pattern on `IPolicyRegistry`, which also
    ///         has no confirmation argument and relies on its distinct
    ///         name for accidental-misuse protection.
    function renounceLastAdmin() external;

    /// @notice Sets the admin role for `role`. Caller MUST hold the
    ///         current admin role for `role`. Useful for delegating role
    ///         management to a different role hierarchy.
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external;

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice The set of `PausableFeature`s currently paused on this
    ///         token. Returns an empty array when nothing is paused.
    ///         Order is implementation-defined; callers should treat the
    ///         result as a set, not a sequence.
    function pausedFeatures() external view returns (PausableFeature[] memory);

    /// @notice Whether `feature` is currently paused. O(1) regardless of
    ///         how many features are paused.
    function isPaused(PausableFeature feature) external view returns (bool);

    /// @notice Pauses the `features` operations. Additive: features
    ///         already paused remain paused, and the listed features
    ///         become paused (duplicates within the call are idempotent).
    ///         Requires `PAUSE_ROLE`. Reverts with `EmptyFeatureSet` if
    ///         `features.length == 0`.
    function pause(PausableFeature[] calldata features) external;

    /// @notice Unpauses the `features` operations. Listed features
    ///         become unpaused; features not listed are unaffected
    ///         (duplicates are idempotent; unpausing a feature that is
    ///         not currently paused is a no-op for that feature).
    ///         Requires `UNPAUSE_ROLE`. Reverts with `EmptyFeatureSet`
    ///         if `features.length == 0`.
    function unpause(PausableFeature[] calldata features) external;

    /*//////////////////////////////////////////////////////////////
                                 POLICY
    //////////////////////////////////////////////////////////////*/

    /// @notice The current policy ID configured for `policyScope`. Returns
    ///         `0` (always-allow built-in) for any policy slot that has
    ///         never been assigned. Reverts `UnsupportedPolicyType` for
    ///         a `policyScope` not supported by this token (or its
    ///         variant). Standard policy types are exposed as the
    ///         role-identifier constants `TRANSFER_SENDER_POLICY()`,
    ///         `TRANSFER_RECEIVER_POLICY()`, `TRANSFER_EXECUTOR_POLICY()`,
    ///         and `MINT_RECEIVER_POLICY()`. Variants add their own
    ///         constants for variant-specific operations (e.g.
    ///         `REDEEM_SENDER_POLICY()` on `IB20Asset`).
    /// @dev    All slots default to `0` (always-allow) at token creation:
    ///         newly created tokens are unrestricted until the admin
    ///         points each slot at a concrete policy. To explicitly
    ///         hard-deny a slot (e.g. disabling redemption on a
    ///         non-redeemable token), point it at the ALWAYS_BLOCK
    ///         sentinel.
    function policyId(bytes32 policyScope) external view returns (uint64);

    /// @notice Updates the policy ID assigned to `policyScope`. Requires
    ///         `DEFAULT_ADMIN_ROLE`. The target policy MUST exist in the
    ///         registry (or be one of the built-in IDs `0` or
    ///         `type(uint64).max`); otherwise reverts with
    ///         `PolicyNotFound`. Takes effect immediately for the next
    ///         operation that consults this slot. Emits `PolicyUpdated`.
    function updatePolicy(bytes32 policyScope, uint64 newPolicyId) external;

    /*//////////////////////////////////////////////////////////////
                              SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    /// @notice The maximum total supply enforced on `mint`. A value of
    ///         `type(uint256).max` indicates no cap (the default for
    ///         tokens that do not specify a cap at creation).
    function supplyCap() external view returns (uint256);

    /// @notice Sets a new supply cap. Requires `DEFAULT_ADMIN_ROLE`.
    ///         Reverts with `InvalidSupplyCap` if the new cap is below
    ///         the current `totalSupply` (we never invalidate
    ///         already-issued supply). The cap may be raised or lowered
    ///         freely otherwise. Emits `SupplyCapUpdated`.
    function updateSupplyCap(uint256 newSupplyCap) external;

    /*//////////////////////////////////////////////////////////////
                       PERMIT (EIP-2612 + ERC-5267)
    //////////////////////////////////////////////////////////////*/

    /// @notice The current EIP-712 domain separator for this token.
    ///         Computed dynamically each call so it remains correct
    ///         after a chain fork that changes `block.chainid` and
    ///         after any `updateName(...)` that mutates `name`.
    /// @dev    Domain content: `(name, version, chainId, verifyingContract)`.
    ///         `name` is the live `name()` value, re-hashed on each
    ///         call. `version` is the constant string `"1"`. `salt`
    ///         is unused (empty). Type hash is
    ///         `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`,
    ///         the canonical EIP-2612 shape.
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
    /// @dev    `fields` is `0x0f` (bits 0, 1, 2, 3 set — `name`,
    ///         `version`, `chainId`, `verifyingContract` are
    ///         populated). `name` is the live `name()` value;
    ///         `version` is the constant string `"1"`. `salt` is
    ///         zero and `extensions` is empty.
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

    /// @notice Updates `contractURI`. Requires `METADATA_ROLE`. Emits
    ///         the parameterless `ContractURIUpdated` event per ERC-7572;
    ///         integrators re-fetch `contractURI()` after observing it.
    function updateContractURI(string calldata newURI) external;
}
