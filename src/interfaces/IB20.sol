// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IB20
///
/// @notice The base Solidity surface every Base-native token (B-20) implements. Variants
///         (Asset, Stablecoin) extend this interface; nothing on this surface is
///         variant-specific.
interface IB20 {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Pausable operation classes. Append-only across protocol versions; existing values are stable.
    ///
    /// @param TRANSFER `transfer`, `transferFrom`, and memo'd variants.
    /// @param MINT     `mint` and `mintWithMemo`.
    /// @param BURN     `burn`, `burnWithMemo`, and `burnBlocked`.
    enum PausableFeature {
        TRANSFER,
        MINT,
        BURN
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH was attached to a call targeting a nonpayable token selector.
    ///
    /// @dev The precompile checks `msg.value != 0` at the top of dispatch before any other
    ///      validation. All B-20 token selectors are nonpayable.
    error NonPayable();

    /// @notice `account` does not hold `neededRole`.
    ///
    /// @param account    Account that failed the role check.
    /// @param neededRole Role the account was required to hold.
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /// @notice Caller failed a positional authorization check that is not expressible as "missing role X".
    error Unauthorized();

    /// @notice The `PausableFeature` covering this operation is currently paused.
    ///
    /// @param feature Paused feature that gated the operation.
    error ContractPaused(PausableFeature feature);

    /// @notice `spender`'s allowance is less than `needed` for the requested `transferFrom`.
    ///
    /// @param spender   Spender whose allowance was insufficient.
    /// @param allowance Current allowance.
    /// @param needed    Allowance required.
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice `sender`'s balance is less than `needed` for the requested transfer or burn.
    ///
    /// @param sender  Account whose balance was insufficient.
    /// @param balance Current balance.
    /// @param needed  Balance required.
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice The transfer's source address is invalid (typically `address(0)`).
    error InvalidSender(address sender);

    /// @notice The transfer's destination address is invalid (typically `address(0)`).
    error InvalidReceiver(address receiver);

    /// @notice The approval's `owner` address is invalid (typically `address(0)`).
    error InvalidApprover(address approver);

    /// @notice The approval's `spender` address is invalid (typically `address(0)`).
    error InvalidSpender(address spender);

    /// @notice An amount argument was zero where a non-zero value is required. Not used for ERC-20 amount arguments.
    error InvalidAmount();

    /// @notice An empty array was passed to a function that requires at least one element.
    error EmptyFeatureSet();

    /// @notice The proposed supply cap is outside the permitted range: below the current
    ///         `totalSupply`, or above the maximum (`type(uint128).max`).
    ///
    /// @param currentSupply Current `totalSupply`.
    /// @param proposedCap   Rejected proposed cap.
    error InvalidSupplyCap(uint256 currentSupply, uint256 proposedCap);

    /// @notice The mint would push `totalSupply` past the configured cap.
    ///
    /// @param cap       Configured supply cap.
    /// @param attempted Resulting supply that would exceed the cap.
    error SupplyCapExceeded(uint256 cap, uint256 attempted);

    /// @notice A policy slot denied the operation.
    ///
    /// @param policyScope Scope of the slot that denied (e.g. `TRANSFER_SENDER_POLICY`).
    /// @param policyId    Policy ID currently configured in that slot.
    error PolicyForbids(bytes32 policyScope, uint64 policyId);

    /// @notice The provided policy ID does not exist in the policy registry.
    error PolicyNotFound(uint64 policyId);

    /// @notice `policyScope` is not a slot this token (or its variant) supports.
    error UnsupportedPolicyType(bytes32 policyScope);

    /// @notice `burnBlocked` was called against a `from` that is currently authorized under `TRANSFER_SENDER_POLICY`.
    error AccountNotBlocked(address account);

    /// @notice An EIP-2612 `permit` was submitted with a `deadline` strictly less than `block.timestamp`.
    error ExpiredSignature(uint256 deadline);

    /// @notice ECDSA recovery on an EIP-2612 `permit` returned `signer`, which does not match the claimed `owner`.
    ///
    /// @param signer Recovered signer.
    /// @param owner  Claimed owner.
    error InvalidSigner(address signer, address owner);

    /// @notice `renounceRole(DEFAULT_ADMIN_ROLE, ...)` was called by the sole remaining admin.
    error LastAdminCannotRenounce();

    /// @notice `renounceLastAdmin()` was called when other accounts also hold `DEFAULT_ADMIN_ROLE`.
    error NotSoleAdmin();

    /// @notice The `callerConfirmation` argument to `renounceRole` was not `msg.sender`.
    error AccessControlBadConfirmation();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-20 transfer event. Emitted on every successful transfer (including memo'd variants),
    ///         mint (`from = address(0)`), and burn (`to = address(0)`, including `burnBlocked`).
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice ERC-20 approval event. Emitted by `approve` and `permit`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice Emitted by `transferWithMemo`, `transferFromWithMemo`, `mintWithMemo`, and `burnWithMemo`
    ///         immediately after the underlying `Transfer` event. `caller` is the `msg.sender` of the memo'd call.
    event Memo(address indexed caller, bytes32 indexed memo);

    /// @notice Emitted by `burnBlocked` in addition to `Transfer(from, address(0), amount)`.
    event BurnedBlocked(address indexed caller, address indexed from, uint256 amount);

    /// @notice Emitted when `account` is granted `role`. `sender` is the originating caller.
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted when `role` is revoked from `account`. `sender` is the originating caller
    ///         (the admin role bearer via `revokeRole`, or `account` itself via `renounceRole`).
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted by `setRoleAdmin` when the admin role for `role` changes.
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /// @notice Emitted by `renounceLastAdmin` in addition to the standard
    ///         `RoleRevoked(DEFAULT_ADMIN_ROLE, previousAdmin, previousAdmin)` event.
    event LastAdminRenounced(address indexed previousAdmin);

    /// @notice Emitted by `pause`. `features` is the argument to the call (not the resulting paused state).
    event Paused(address indexed updater, PausableFeature[] features);

    /// @notice Emitted by `unpause`. `features` is the argument to the call (not the resulting paused state).
    event Unpaused(address indexed updater, PausableFeature[] features);

    /// @notice Emitted by `updatePolicy` when a token's policy slot is changed. Initial slot assignment at
    ///         creation is also emitted via `PolicyUpdated` with `oldPolicyId == 0`.
    event PolicyUpdated(bytes32 indexed policyScope, uint64 oldPolicyId, uint64 newPolicyId);

    /// @notice Emitted by `updateSupplyCap`.
    event SupplyCapUpdated(address indexed updater, uint256 oldSupplyCap, uint256 newSupplyCap);

    /// @notice Emitted by `updateContractURI`. Per ERC-7572, parameterless: integrators re-fetch `contractURI()`.
    event ContractURIUpdated();

    /// @notice Emitted by `updateName`. Carries the new name string.
    event NameUpdated(address indexed updater, string newName);

    /// @notice Emitted by `updateSymbol`. Carries the new symbol string.
    event SymbolUpdated(address indexed updater, string newSymbol);

    /// @notice ERC-5267 domain-change signal. Emitted exactly once per successful `updateName` call,
    ///         immediately after `NameUpdated`. `updateSymbol` does NOT emit this event.
    event EIP712DomainChanged();

    /*//////////////////////////////////////////////////////////////
                              ROLE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The default top-level admin role (`bytes32(0)`). Required to call `grantRole`, `revokeRole`,
    ///         `setRoleAdmin`, `updatePolicy`, and `updateSupplyCap`.
    /// @return Role constant.
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Required to call `mint` and `mintWithMemo`.
    /// @return Role constant.
    function MINT_ROLE() external view returns (bytes32);

    /// @notice Required to call `burn` and `burnWithMemo`.
    /// @return Role constant.
    function BURN_ROLE() external view returns (bytes32);

    /// @notice Required to call `burnBlocked`.
    /// @return Role constant.
    function BURN_BLOCKED_ROLE() external view returns (bytes32);

    /// @notice Required to call `pause`.
    /// @return Role constant.
    function PAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `unpause`.
    /// @return Role constant.
    function UNPAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `updateName`, `updateSymbol`, and `updateContractURI`.
    /// @return Role constant.
    function METADATA_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          POLICY TYPE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy slot consulted against `from` on every transfer (including `transferFrom`).
    /// @dev Bypassed for factory-originated calls during the creation (bootstrap) window; see
    ///      `IB20Factory.createB20`.
    /// @return Policy scope constant.
    function TRANSFER_SENDER_POLICY() external view returns (bytes32);

    /// @notice Policy slot consulted against `to` on every transfer.
    /// @dev Bypassed for factory-originated calls during the creation (bootstrap) window; see
    ///      `IB20Factory.createB20`.
    /// @return Policy scope constant.
    function TRANSFER_RECEIVER_POLICY() external view returns (bytes32);

    /// @notice Policy slot consulted against `msg.sender` on `transferFrom` when distinct from `from`.
    ///         Not consulted on `transfer`.
    /// @dev Bypassed for factory-originated calls during the creation (bootstrap) window; see
    ///      `IB20Factory.createB20`.
    /// @return Policy scope constant.
    function TRANSFER_EXECUTOR_POLICY() external view returns (bytes32);

    /// @notice Policy slot consulted against `to` on every mint.
    /// @dev Unlike the transfer-side policies, this slot is ALWAYS enforced — including for
    ///      factory-originated mints during the creation (bootstrap) window — so new supply is never
    ///      issued to a policy-denied recipient even at creation. See `IB20Factory.createB20`.
    /// @return Policy scope constant.
    function MINT_RECEIVER_POLICY() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                  ERC-20
    //////////////////////////////////////////////////////////////*/

    /// @notice Token name. Set at creation, mutable via `updateName`.
    /// @return Current token name.
    function name() external view returns (string memory);

    /// @notice Token symbol. Set at creation, mutable via `updateSymbol`.
    /// @return Current token symbol.
    function symbol() external view returns (string memory);

    /// @notice Number of decimal places. Immutable per token variant.
    /// @return Number of decimal places.
    function decimals() external view returns (uint8);

    /// @notice Total token supply currently in circulation.
    /// @return Current total supply.
    function totalSupply() external view returns (uint256);

    /// @notice Balance of `account`.
    ///
    /// @param account Account whose balance is being queried.
    ///
    /// @return Current balance.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Allowance granted by `owner` to `spender`.
    ///
    /// @param owner   Allowance owner.
    /// @param spender Allowance spender.
    ///
    /// @return Current allowance.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Transfers `amount` from `msg.sender` to `to`. Emits `Transfer`.
    ///
    /// @dev Reverts with `ContractPaused(TRANSFER)` when `TRANSFER` is paused.
    /// @dev Reverts with `InvalidReceiver` when `to == address(0)`.
    /// @dev Reverts with `InvalidSender` when `msg.sender == address(0)`.
    /// @dev Reverts with `PolicyForbids(TRANSFER_SENDER_POLICY, ...)` when `msg.sender` is not authorized.
    /// @dev Reverts with `PolicyForbids(TRANSFER_RECEIVER_POLICY, ...)` when `to` is not authorized.
    /// @dev Reverts with `InsufficientBalance` when `msg.sender`'s balance is below `amount`.
    ///
    /// @param to     Destination address.
    /// @param amount Amount to transfer.
    ///
    /// @return Always `true` on success.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` from `from` to `to` using `msg.sender`'s allowance. Emits `Transfer`.
    ///
    /// @dev Reverts with `ContractPaused(TRANSFER)` when `TRANSFER` is paused.
    /// @dev Reverts with `InvalidReceiver` when `to == address(0)`.
    /// @dev Reverts with `InvalidSender` when `from == address(0)`.
    /// @dev Reverts with `InsufficientAllowance` when the caller's allowance from `from` is below `amount`.
    /// @dev Reverts with `PolicyForbids(TRANSFER_EXECUTOR_POLICY, ...)` when `msg.sender != from` and `msg.sender` is not authorized.
    /// @dev Reverts with `PolicyForbids(TRANSFER_SENDER_POLICY, ...)` when `from` is not authorized.
    /// @dev Reverts with `PolicyForbids(TRANSFER_RECEIVER_POLICY, ...)` when `to` is not authorized.
    /// @dev Reverts with `InsufficientBalance` when `from`'s balance is below `amount`.
    ///
    /// @param from   Source address.
    /// @param to     Destination address.
    /// @param amount Amount to transfer.
    ///
    /// @return Always `true` on success.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Sets `spender`'s allowance to `amount`. Not gated by any policy or by pause. Emits `Approval`.
    ///
    /// @dev Reverts with `InvalidApprover` when `msg.sender == address(0)`.
    /// @dev Reverts with `InvalidSpender` when `spender == address(0)`.
    ///
    /// @param spender Account being granted the allowance.
    /// @param amount  Allowance amount.
    ///
    /// @return Always `true` on success.
    function approve(address spender, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                            METADATA UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the token's `name`. Emits `NameUpdated` followed by `EIP712DomainChanged`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `METADATA_ROLE`.
    ///
    /// @param newName New token name.
    function updateName(string calldata newName) external;

    /// @notice Updates the token's `symbol`. Emits `SymbolUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `METADATA_ROLE`.
    ///
    /// @param newSymbol New token symbol.
    function updateSymbol(string calldata newSymbol) external;

    /*//////////////////////////////////////////////////////////////
                          MEMO TRANSFER VARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Same as `transfer`, plus emits `Memo` immediately after the standard `Transfer` event.
    ///         A memo of `bytes32(0)` is permitted.
    ///
    /// @param to     Destination address.
    /// @param amount Amount to transfer.
    /// @param memo   Off-chain memo payload.
    ///
    /// @return Always `true` on success.
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external returns (bool);

    /// @notice Same as `transferFrom`, plus emits `Memo` immediately after the standard `Transfer` event.
    ///         A memo of `bytes32(0)` is permitted.
    ///
    /// @param from   Source address.
    /// @param to     Destination address.
    /// @param amount Amount to transfer.
    /// @param memo   Off-chain memo payload.
    ///
    /// @return Always `true` on success.
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              MINT / BURN
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amount` to `to`. Emits `Transfer(address(0), to, amount)`.
    ///
    /// @dev Reverts with `ContractPaused(MINT)` when `MINT` is paused.
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `MINT_ROLE`.
    /// @dev Reverts with `InvalidReceiver` when `to == address(0)`.
    /// @dev Reverts with `PolicyForbids(MINT_RECEIVER_POLICY, ...)` when `to` is not authorized.
    /// @dev Reverts with `SupplyCapExceeded` when `totalSupply + amount > supplyCap`.
    ///
    /// @param to     Mint recipient.
    /// @param amount Amount to mint.
    function mint(address to, uint256 amount) external;

    /// @notice Same as `mint`, plus emits `Memo` immediately after the standard `Transfer` event.
    ///         A memo of `bytes32(0)` is permitted.
    ///
    /// @param to     Mint recipient.
    /// @param amount Amount to mint.
    /// @param memo   Off-chain memo payload.
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external;

    /// @notice Burns `amount` from the caller's own balance. Not subject to any policy.
    ///         Emits `Transfer(caller, address(0), amount)`.
    ///
    /// @dev Reverts with `ContractPaused(BURN)` when `BURN` is paused.
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `BURN_ROLE`.
    /// @dev Reverts with `InsufficientBalance` when the caller's balance is below `amount`.
    ///
    /// @param amount Amount to burn.
    function burn(uint256 amount) external;

    /// @notice Same as `burn`, plus emits `Memo` immediately after the standard `Transfer` event.
    ///         A memo of `bytes32(0)` is permitted.
    ///
    /// @param amount Amount to burn.
    /// @param memo   Off-chain memo payload.
    function burnWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice Destroys `amount` of `from`'s balance. Emits `Transfer(from, address(0), amount)` and
    ///         `BurnedBlocked(caller, from, amount)`.
    ///
    /// @dev Reverts with `ContractPaused(BURN)` when `BURN` is paused.
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `BURN_BLOCKED_ROLE`.
    /// @dev Reverts with `AccountNotBlocked` when `from` is currently authorized under `TRANSFER_SENDER_POLICY`.
    /// @dev Reverts with `InsufficientBalance` when `from`'s balance is below `amount`.
    ///
    /// @param from   Account whose balance is being seized.
    /// @param amount Amount to burn.
    function burnBlocked(address from, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `account` is a member of `role`. User-defined roles are supported and have no
    ///         built-in effect on the token's own functions.
    ///
    /// @param role    Role to check.
    /// @param account Account to check.
    ///
    /// @return Whether `account` holds `role`.
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @notice The role required to grant or revoke `role`. Defaults to `DEFAULT_ADMIN_ROLE` if not
    ///         explicitly set via `setRoleAdmin`.
    ///
    /// @param role Role whose admin is being queried.
    ///
    /// @return Admin role.
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /// @notice Grants `role` to `account`. Emits `RoleGranted`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold the admin role for `role`,
    ///      or when the token has been transitioned to admin-less via `renounceLastAdmin` (admin-resurrection guard).
    ///
    /// @param role    Role to grant.
    /// @param account Recipient.
    function grantRole(bytes32 role, address account) external;

    /// @notice Revokes `role` from `account`. Emits `RoleRevoked`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold the admin role for `role`,
    ///      or when the token has been transitioned to admin-less via `renounceLastAdmin`.
    /// @dev Reverts with `LastAdminCannotRenounce` when `role == DEFAULT_ADMIN_ROLE` and `account` is the last default admin.
    ///      Use `renounceLastAdmin` to clear the final admin.
    ///
    /// @param role    Role to revoke.
    /// @param account Account to revoke from.
    function revokeRole(bytes32 role, address account) external;

    /// @notice Caller renounces `role` for themselves. Emits `RoleRevoked`.
    ///
    /// @dev Reverts with `AccessControlBadConfirmation` when `callerConfirmation != msg.sender`.
    /// @dev Reverts with `LastAdminCannotRenounce` when `role == DEFAULT_ADMIN_ROLE` and the caller is the last default admin.
    ///
    /// @param role               Role to renounce.
    /// @param callerConfirmation MUST equal `msg.sender`.
    function renounceRole(bytes32 role, address callerConfirmation) external;

    /// @notice Permanently transitions the token to a zero-admin state. Revokes `DEFAULT_ADMIN_ROLE`
    ///         from `msg.sender`. Emits `RoleRevoked(DEFAULT_ADMIN_ROLE, msg.sender, msg.sender)` and
    ///         `LastAdminRenounced(msg.sender)`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when `msg.sender` does not hold `DEFAULT_ADMIN_ROLE`.
    /// @dev Reverts with `NotSoleAdmin` when other accounts also hold `DEFAULT_ADMIN_ROLE`.
    function renounceLastAdmin() external;

    /// @notice Sets the admin role for `role`. Emits `RoleAdminChanged`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold the current admin role for `role`,
    ///      or when the token has been transitioned to admin-less via `renounceLastAdmin`.
    ///
    /// @param role         Role whose admin is being updated.
    /// @param newAdminRole New admin role.
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external;

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice The `PausableFeature`s currently paused on this token. Order is implementation-defined;
    ///         callers should treat the result as a set.
    /// @return Currently-paused features.
    function pausedFeatures() external view returns (PausableFeature[] memory);

    /// @notice Whether `feature` is currently paused. O(1).
    ///
    /// @param feature Feature to query.
    ///
    /// @return Whether `feature` is paused.
    function isPaused(PausableFeature feature) external view returns (bool);

    /// @notice Pauses each of `features`. Additive: features already paused remain paused; duplicates
    ///         within the call are idempotent. Emits `Paused`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `PAUSE_ROLE`.
    /// @dev Reverts with `EmptyFeatureSet` when `features.length == 0`.
    ///
    /// @param features Features to pause.
    function pause(PausableFeature[] calldata features) external;

    /// @notice Unpauses each of `features`. Features not listed are unaffected; duplicates are idempotent.
    ///         Emits `Unpaused`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `UNPAUSE_ROLE`.
    /// @dev Reverts with `EmptyFeatureSet` when `features.length == 0`.
    ///
    /// @param features Features to unpause.
    function unpause(PausableFeature[] calldata features) external;

    /*//////////////////////////////////////////////////////////////
                                 POLICY
    //////////////////////////////////////////////////////////////*/

    /// @notice The current policy ID configured for `policyScope`. Returns `0` (always-allow built-in)
    ///         for any slot that has never been assigned.
    ///
    /// @dev Reverts with `UnsupportedPolicyType` when `policyScope` is not recognized by this token.
    ///
    /// @param policyScope Policy slot scope.
    ///
    /// @return Configured policy ID.
    function policyId(bytes32 policyScope) external view returns (uint64);

    /// @notice Updates the policy ID assigned to `policyScope`. Takes effect immediately for the next
    ///         operation that consults this slot. Emits `PolicyUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `DEFAULT_ADMIN_ROLE`.
    /// @dev Reverts with `UnsupportedPolicyType` when `policyScope` is not recognized by this token.
    /// @dev Reverts with `PolicyNotFound` when `newPolicyId` is not a built-in sentinel and does not exist in the registry.
    ///
    /// @param policyScope Policy slot scope.
    /// @param newPolicyId Policy ID to assign to the slot.
    function updatePolicy(bytes32 policyScope, uint64 newPolicyId) external;

    /*//////////////////////////////////////////////////////////////
                              SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    /// @notice The maximum total supply enforced on `mint`. Capped at `type(uint128).max`, which
    ///         indicates no cap (the unbounded sentinel). `totalSupply` can therefore never exceed
    ///         `type(uint128).max`.
    /// @return Current supply cap.
    function supplyCap() external view returns (uint256);

    /// @notice Sets a new supply cap. May be raised or lowered freely, but never below current
    ///         `totalSupply` and never above `type(uint128).max`. Emits `SupplyCapUpdated`.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `DEFAULT_ADMIN_ROLE`.
    /// @dev Reverts with `InvalidSupplyCap` when `newSupplyCap < totalSupply()` or `newSupplyCap > type(uint128).max`.
    ///
    /// @param newSupplyCap New supply cap. Must not exceed `type(uint128).max`.
    function updateSupplyCap(uint256 newSupplyCap) external;

    /*//////////////////////////////////////////////////////////////
                       PERMIT (EIP-2612 + ERC-5267)
    //////////////////////////////////////////////////////////////*/

    /// @notice The current EIP-712 domain separator for this token. Recomputed on each call so it
    ///         remains correct after `updateName` or a chain fork that changes `block.chainid`.
    /// @return Current domain separator.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The current EIP-2612 permit nonce for `owner`. Incremented by 1 on each successful `permit`.
    ///
    /// @param owner Account whose nonce is being queried.
    ///
    /// @return Current nonce.
    function nonces(address owner) external view returns (uint256);

    /// @notice EIP-2612 permit. Recovers `owner` via ECDSA from `(v, r, s)`. EOA signatures only;
    ///         ERC-1271 contract signatures are NOT supported. Emits `Approval`.
    ///
    /// @dev Reverts with `ExpiredSignature` when `block.timestamp > deadline`.
    /// @dev Reverts with `InvalidSigner` when ECDSA recovery does not yield `owner`.
    /// @dev Reverts with `InvalidSpender` when `spender == address(0)`.
    ///
    /// @param owner    Token holder granting the allowance.
    /// @param spender  Account being granted the allowance.
    /// @param value    Allowance amount.
    /// @param deadline Unix timestamp after which the signature is invalid.
    /// @param v        ECDSA recovery byte.
    /// @param r        ECDSA signature r component.
    /// @param s        ECDSA signature s component.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /// @notice ERC-5267 EIP-712 domain introspection.
    ///
    /// @return fields            Bitmap of populated domain fields (`0x0f`: `name`, `version`, `chainId`, `verifyingContract`).
    /// @return name              Live `name()` value.
    /// @return version           Constant `"1"`.
    /// @return chainId           Current `block.chainid`.
    /// @return verifyingContract This token's address.
    /// @return salt              Unused (zero).
    /// @return extensions        Empty.
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

    /// @notice Off-chain URI pointing at contract-level metadata for this token, per ERC-7572.
    /// @return Current contract URI.
    function contractURI() external view returns (string memory);

    /// @notice Updates `contractURI`. Emits the parameterless `ContractURIUpdated` event per ERC-7572;
    ///         integrators re-fetch `contractURI()` after observing it.
    ///
    /// @dev Reverts with `AccessControlUnauthorizedAccount` when the caller does not hold `METADATA_ROLE`.
    ///
    /// @param newURI New contract URI.
    function updateContractURI(string calldata newURI) external;
}
