// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IB20
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
///         six named roles (`DEFAULT_ADMIN_ROLE`, `MINT_ROLE`, `BURN_ROLE`,
///         `BURN_BLOCKED_ROLE`, `PAUSE_ROLE`, `UNPAUSE_ROLE`) plus arbitrary
///         user-defined roles. `grantRole`, `revokeRole`, `renounceRole`, and
///         `setRoleAdmin` work uniformly across all roles. The only
///         protocol-level constraint is that the LAST holder of
///         `DEFAULT_ADMIN_ROLE` cannot renounce: the token must always have
///         at least one admin.
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
///         **Policy model.** The token holds a generic `policyId` mapping
///         keyed by `bytes32 policyType`, where each standard policy type
///         is the `keccak256` hash of its name. Five standard types are
///         exposed as constants:
///         - `TRANSFER_SENDER`   — checked against `from` on every transfer
///         - `TRANSFER_RECEIVER` — checked against `to`   on every transfer
///         - `TRANSFER_EXECUTOR` — checked against `msg.sender` on `transferFrom`
///                                  (when distinct from `from`)
///         - `MINT_RECEIVER`     — checked against `to`   on every mint
///         - `REDEEMER_SENDER`   — checked against `msg.sender` on `redeem`
///                                  (used by variants that ship redeem,
///                                  e.g. IB20Security)
///         Each policy slot defaults to built-in ID `0` (always-reject) so
///         newly minted tokens cannot move balance until the admin
///         configures their compliance regime. ID `1` (always-allow) is
///         the explicit opt-out for a given role.
///
///         Asymmetric per-role configuration is expressed by pointing
///         different slots at different policies — for example, a
///         sanctions BLOCKLIST on `TRANSFER_SENDER` and an unrestricted
///         always-allow on `MINT_RECEIVER`. The registry stays flat;
///         all composition happens at the token layer.
///
///         `approve` is NOT gated by any policy (only the act of MOVING
///         balance is gated).
///
///         **Permit.** EIP-2612 permit, EOA signatures only. ERC-1271
///         contract signatures are NOT supported on the default surface
///         (smart-contract accounts use call-batching or paymaster flows
///         instead to set allowances). EIP-712 domain is
///         `(chainId, verifyingContract)` only, with `name` and `version`
///         empty. ERC-5267 `eip712Domain()` is exposed for domain
///         introspection by integrators.
interface IB20 {
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

    /// @notice One or more pause vectors covering this operation are
    ///         currently set. `pausedVector` is the specific vector that
    ///         blocked the call.
    error ContractPaused(uint256 pausedVector);

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
    ///         required (e.g. `pause(0)`). NOT used for ERC-20 amount
    ///         arguments: per OZ / ERC-6093, ERC-20 functions do not
    ///         validate `amount > 0`.
    error InvalidAmount();

    /// @notice The proposed supply cap is below the current `totalSupply`,
    ///         which would invalidate already-issued supply.
    error InvalidSupplyCap(uint256 currentSupply, uint256 proposedCap);

    /// @notice The mint would push `totalSupply` past the configured cap.
    error SupplyCapExceeded(uint256 cap, uint256 attempted);

    /// @notice A policy slot denied the operation. `policyType` identifies
    ///         which slot (e.g. `TRANSFER_SENDER`, `MINT_RECEIVER`) and
    ///         `policyId` is the ID currently set in that slot.
    error PolicyForbids(bytes32 policyType, uint64 policyId);

    /// @notice The provided policy ID does not exist in the policy
    ///         registry.
    error PolicyNotFound(uint64 policyId);

    /// @notice `burnBlocked` was called against a `from` address that is
    ///         currently authorized under the active `TRANSFER_SENDER`
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

    /// @notice The capability bit for this operation is not set on the
    ///         token. Capability state is immutable; this revert is
    ///         permanent.
    error FeatureDisabled(uint256 capability);

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
    ///         (`from = address(0)`), and burn (`to = address(0)`,
    ///         including `burnBlocked` and `redeem`).
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
    ///         `setRoleAdmin`.
    /// @dev    Matches OZ AccessControl's `RoleAdminChanged` event exactly.
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /// @notice Emitted by `pause`. `vectors` is the bitmask argument to
    ///         the call (not the resulting paused state). `updater` is
    ///         the caller.
    event Paused(address indexed updater, uint256 vectors);

    /// @notice Emitted by `unpause`. All paused vectors are cleared.
    event Unpaused(address indexed updater);

    /// @notice Emitted by `updatePolicy` when a token's policy slot is
    ///         changed. `policyType` is one of the standard policy-type
    ///         identifiers (e.g. `TRANSFER_SENDER()`); `oldPolicyId` and
    ///         `newPolicyId` are the prior and current registry IDs for
    ///         that slot. Initial slot assignment at creation is also
    ///         emitted via `PolicyUpdated` with `oldPolicyId == 0`.
    event PolicyUpdated(bytes32 indexed policyType, uint64 oldPolicyId, uint64 newPolicyId);

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

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The default top-level admin role, equal to `bytes32(0)` per
    ///         the OpenZeppelin AccessControl convention. The admin
    ///         manages all other roles via `grantRole`, `revokeRole`, and
    ///         `setRoleAdmin`. The admin can also `updatePolicy`,
    ///         `setSupplyCap`, `setContractURI`, `setName`, and `setSymbol`.
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
    ///         active `TRANSFER_SENDER` policy) can be granted only to a
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

    /*//////////////////////////////////////////////////////////////
                          POLICY TYPE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The policy slot consulted against `from` on every transfer
    ///         (including the `from` side of `transferFrom`). Identifier
    ///         is `keccak256("TRANSFER_SENDER")`.
    function TRANSFER_SENDER() external view returns (bytes32);

    /// @notice The policy slot consulted against `to` on every transfer.
    ///         Identifier is `keccak256("TRANSFER_RECEIVER")`.
    function TRANSFER_RECEIVER() external view returns (bytes32);

    /// @notice The policy slot consulted against `msg.sender` on
    ///         `transferFrom` (the spender, when distinct from `from`).
    ///         Not consulted on `transfer` (where `msg.sender == from`).
    ///         Identifier is `keccak256("TRANSFER_EXECUTOR")`.
    function TRANSFER_EXECUTOR() external view returns (bytes32);

    /// @notice The policy slot consulted against `to` on every mint.
    ///         Identifier is `keccak256("MINT_RECEIVER")`.
    function MINT_RECEIVER() external view returns (bytes32);

    /// @notice The policy slot consulted against `msg.sender` on
    ///         `redeem` (used by variants that ship redeem, e.g.
    ///         IB20Security). Identifier is `keccak256("REDEEMER_SENDER")`.
    ///         Exposed on the base interface so all B-20 tokens share a
    ///         common policy-type vocabulary even when not all slots are
    ///         actively consulted on a given variant.
    function REDEEMER_SENDER() external view returns (bytes32);

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
    ///         - `PolicyForbids(TRANSFER_SENDER,   policyId)` if `msg.sender`
    ///           is not authorized under the active `TRANSFER_SENDER` policy.
    ///         - `PolicyForbids(TRANSFER_RECEIVER, policyId)` if `to` is not
    ///           authorized under the active `TRANSFER_RECEIVER` policy.
    ///         - `InsufficientBalance(msg.sender, balance, amount)` if the
    ///           caller does not have enough balance.
    ///         - `InvalidReceiver(to)` if `to == address(0)`.
    /// @dev    Does NOT consult the `TRANSFER_EXECUTOR` policy: on direct
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
    ///         - `PolicyForbids(TRANSFER_EXECUTOR, policyId)` if
    ///           `msg.sender != from` and `msg.sender` is not authorized
    ///           under the active `TRANSFER_EXECUTOR` policy.
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
    ///         3. `to` is authorized under the active `MINT_RECEIVER`
    ///            policy (else `PolicyForbids(MINT_RECEIVER, policyId)`).
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
    ///         `BURN_ROLE`. Subject to the `BURN` pause vector being unset
    ///         (else `ContractPaused(BURN)`). NOT subject to any policy:
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
    ///         1. The `BURN` pause vector is unset (else
    ///            `ContractPaused(BURN)`).
    ///         2. `from` is NOT authorized under the active
    ///            `TRANSFER_SENDER` policy (else `AccountNotBlocked(from)`).
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
    function pause(uint256 vectors) external;

    /// @notice Unpauses ALL currently-paused vectors. Requires `PAUSABLE`
    ///         capability and `UNPAUSE_ROLE`. The Default surface does
    ///         not support unpausing a subset of vectors; admin must
    ///         unpause everything and re-pause the still-blocked vectors
    ///         in a follow-up call if granular resumption is desired.
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                                 POLICY
    //////////////////////////////////////////////////////////////*/

    /// @notice The current policy ID configured for `policyType`. Returns
    ///         `0` (always-reject built-in) for any policy slot that has
    ///         never been assigned. Standard policy types are exposed as
    ///         the role-identifier constants `TRANSFER_SENDER()`,
    ///         `TRANSFER_RECEIVER()`, `TRANSFER_EXECUTOR()`,
    ///         `MINT_RECEIVER()`, and `REDEEMER_SENDER()`; user-defined
    ///         policy types are also supported and may be used by
    ///         variant-specific functions.
    /// @dev    All slots default to `0` (always-reject) at token creation:
    ///         newly minted tokens cannot move balance until the admin
    ///         configures their policy slots. To explicitly opt out of a
    ///         given slot's enforcement, point it at `1` (always-allow).
    function policyId(bytes32 policyType) external view returns (uint64);

    /// @notice Updates the policy ID assigned to `policyType`. Requires
    ///         `DEFAULT_ADMIN_ROLE`. The target policy MUST exist in the
    ///         registry (or be one of the built-in IDs `0` or `1`);
    ///         otherwise reverts with `PolicyNotFound`. Takes effect
    ///         immediately for the next operation that consults this
    ///         slot. Emits `PolicyUpdated`.
    function updatePolicy(bytes32 policyType, uint64 newPolicyId) external;

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
