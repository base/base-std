// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IDefaultToken
/// @notice The base Solidity surface every Base-native token (B-20) implements.
///         Variants (Stablecoin, Security, ...) extend this interface; nothing
///         on this surface is variant-specific. A token created at the Default
///         variant address presents exactly this interface.
/// @dev    Backward-compatible with ERC-20 at the function-selector level:
///         `transfer`, `transferFrom`, `approve`, `balanceOf`, `allowance`,
///         `totalSupply`, `name`, `symbol`, `decimals` all match ERC-20 selectors.
///         Memo'd siblings live alongside, and their existence does not change
///         the ERC-20 selectors any wallet or contract already expects.
///
///         Every token's optional features are gated by an immutable
///         `capabilities()` bitfield set at creation. Functions whose
///         capability bit is unset revert with `FeatureDisabled` regardless
///         of role state. See `Capabilities` for the bit definitions.
interface IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error ContractPaused();
    error AlreadyPaused();
    error NotPaused();
    error InsufficientAllowance();
    error InsufficientBalance(uint256 currentBalance, uint256 requestedAmount);
    error InvalidAmount();
    error InvalidRecipient();
    error InvalidSupplyCap();
    error SupplyCapExceeded();
    error PolicyForbids();
    error ProtectedAddress();
    error PermitExpired();
    error InvalidSignature();
    error FeatureDisabled(uint256 capability);
    error EnforcedDefaultAdminRules();
    error InvalidDefaultAdmin(address account);
    error EnforcedDefaultAdminDelay(uint48 schedule);
    error NoPendingDefaultAdmin();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event TransferWithMemo(address indexed from, address indexed to, uint256 amount, bytes32 indexed memo);

    event Mint(address indexed to, uint256 amount);
    event MintWithMemo(address indexed to, uint256 amount, bytes32 indexed memo);
    event Burn(address indexed from, uint256 amount);
    event BurnWithMemo(address indexed from, uint256 amount, bytes32 indexed memo);
    event BurnBlocked(address indexed from, uint256 amount);

    event RoleMembershipUpdated(bytes32 indexed role, address indexed account, address indexed sender, bool member);
    event RoleAdminUpdated(bytes32 indexed role, bytes32 indexed newAdminRole, address indexed sender);

    event PauseStateUpdated(address indexed updater, bool isPaused);

    event TransferPolicyUpdated(address indexed updater, uint64 indexed newPolicyId);

    event SupplyCapUpdated(address indexed updater, uint256 newSupplyCap);

    event ContractURIUpdated();

    event DefaultAdminTransferScheduled(address indexed newAdmin, uint48 acceptSchedule);
    event DefaultAdminTransferCanceled();
    event DefaultAdminDelayChangeScheduled(uint48 newDelay, uint48 effectSchedule);
    event DefaultAdminDelayChangeCanceled();

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice The default top-level admin role. The admin manages all other
    ///         roles. The DEFAULT_ADMIN_ROLE itself can only be transferred via
    ///         the two-step `beginDefaultAdminTransfer` / `acceptDefaultAdminTransfer`
    ///         flow with a configurable delay; `grantRole` and `revokeRole`
    ///         REVERT when called for `DEFAULT_ADMIN_ROLE`.
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Required to call `mint` / `mintWithMemo`. Held separately from
    ///         BURN_ROLE so issuance and destruction authority can be split
    ///         across teams (e.g. treasury team mints, redemption team burns).
    function MINT_ROLE() external view returns (bytes32);

    /// @notice Required to call `burn` / `burnWithMemo`. See MINT_ROLE for
    ///         rationale on the split.
    function BURN_ROLE() external view returns (bytes32);

    /// @notice Required to call `pause`. Held separately from UNPAUSE_ROLE so
    ///         emergency-stop authority can be delegated to a 24/7 ops team
    ///         without also granting unpause authority.
    function PAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `unpause`. See PAUSE_ROLE for rationale on the split.
    function UNPAUSE_ROLE() external view returns (bytes32);

    /// @notice Required to call `burnBlocked`. Holders may force-burn balance
    ///         from an address that is currently not authorized as a sender by
    ///         the active transfer policy.
    function BURN_BLOCKED_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                              CAPABILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The immutable feature bitfield assigned at creation. Each bit
    ///         indicates that the corresponding optional function CAN be
    ///         called on this token. Bits not set here mean the corresponding
    ///         function reverts with `FeatureDisabled`, permanently. See
    ///         `Capabilities` for the bit definitions.
    function capabilities() external view returns (uint256);

    /// @notice Convenience views for individual capability bits. Each returns
    ///         `(capabilities() & Capabilities.X) != 0`.
    function isPausable() external view returns (bool);
    function isMintable() external view returns (bool);
    function isBurnable() external view returns (bool);
    function isBurnBlockedEnabled() external view returns (bool);
    function isAdminMutable() external view returns (bool);
    function isPolicyMutable() external view returns (bool);
    function isCapMutable() external view returns (bool);
    function isURIMutable() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                  ERC-20
    //////////////////////////////////////////////////////////////*/

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                          MEMO TRANSFER VARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Same as `transfer`, but additionally emits `TransferWithMemo`
    ///         carrying a 32-byte caller-supplied memo. The standard
    ///         `Transfer` event is also emitted for ERC-20 indexer compat.
    /// @dev    A memo of `bytes32(0)` is permitted; it indicates "no memo"
    ///         while still emitting the memo event.
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external returns (bool);

    /// @notice Same as `transferFrom`, with a memo. See `transferWithMemo`.
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              MINT / BURN
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amount` to `to`. Requires `MINTABLE` capability and
    ///         `MINT_ROLE`. Subject to the token's transfer policy: the
    ///         recipient must satisfy `isAuthorizedMintRecipient` on the
    ///         active policy.
    /// @dev    Emits both `Transfer(address(0), to, amount)` (ERC-20) and
    ///         `Mint(to, amount)`.
    function mint(address to, uint256 amount) external;

    /// @notice Same as `mint`, with a 32-byte memo. Emits `MintWithMemo` in
    ///         addition to `Mint` and `Transfer`.
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external;

    /// @notice Burns `amount` from the caller's balance. Requires `BURNABLE`
    ///         capability and `BURN_ROLE`.
    /// @dev    Emits both `Transfer(caller, address(0), amount)` and
    ///         `Burn(caller, amount)`.
    function burn(uint256 amount) external;

    /// @notice Same as `burn`, with a 32-byte memo. Emits `BurnWithMemo` in
    ///         addition to `Burn` and `Transfer`.
    function burnWithMemo(uint256 amount, bytes32 memo) external;

    /// @notice Force-burns `amount` from an address that is currently NOT
    ///         authorized as a sender by the active transfer policy. Used for
    ///         sanctions seizures and similar compliance enforcement.
    /// @dev    Requires `BURN_BLOCKED` capability and `BURN_BLOCKED_ROLE`.
    ///         Reverts with `ProtectedAddress` if `from` IS authorized to
    ///         send under the active policy (i.e. only blocked addresses can
    ///         be force-burned). Emits `Transfer(from, address(0), amount)`
    ///         and `BurnBlocked(from, amount)`.
    function burnBlocked(address from, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns whether `account` is a member of `role`. `role` may be
    ///         any `bytes32` value; user-defined roles are supported and have
    ///         no built-in effect on the token's own functions but may be
    ///         consumed by external contracts.
    function hasRole(bytes32 role, address account) external view returns (bool);

    /// @notice Returns the role required to grant or revoke `role`. Defaults
    ///         to `DEFAULT_ADMIN_ROLE` if not explicitly set via `setRoleAdmin`.
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /// @notice Grants `role` to `account`. Requires `ADMIN_MUTABLE`
    ///         capability and the admin role for `role` (see `getRoleAdmin`).
    /// @dev    REVERTS with `EnforcedDefaultAdminRules` when `role` is
    ///         `DEFAULT_ADMIN_ROLE`. Use `beginDefaultAdminTransfer` for
    ///         that role.
    function grantRole(bytes32 role, address account) external;

    /// @notice Revokes `role` from `account`. Requires `ADMIN_MUTABLE`
    ///         capability and the admin role for `role`.
    /// @dev    REVERTS with `EnforcedDefaultAdminRules` when `role` is
    ///         `DEFAULT_ADMIN_ROLE`. The default admin can only voluntarily
    ///         exit via `renounceRole`.
    function revokeRole(bytes32 role, address account) external;

    /// @notice Caller revokes `role` from themselves. Always permitted, even
    ///         when `ADMIN_MUTABLE` is unset, so role holders can voluntarily
    ///         exit a frozen role configuration.
    /// @dev    Permitted for `DEFAULT_ADMIN_ROLE` and ALSO subject to the
    ///         configured `defaultAdminDelay`: a default-admin renunciation
    ///         is scheduled and only takes effect after the delay elapses.
    ///         Implementations should use the same scheduling machinery as
    ///         `beginDefaultAdminTransfer` (with `newAdmin == address(0)`).
    function renounceRole(bytes32 role) external;

    /// @notice Sets the admin role for `role`. Requires `ADMIN_MUTABLE`
    ///         capability and the current admin role for `role`.
    /// @dev    REVERTS with `EnforcedDefaultAdminRules` when `role` is
    ///         `DEFAULT_ADMIN_ROLE`; the default admin's admin role is
    ///         always itself.
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external;

    /*//////////////////////////////////////////////////////////////
                          TWO-STEP DEFAULT ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice The current holder of `DEFAULT_ADMIN_ROLE`. The default admin
    ///         is always exactly one address (or `address(0)` after a
    ///         completed renunciation).
    function defaultAdmin() external view returns (address);

    /// @notice Returns the address that has been scheduled to receive
    ///         `DEFAULT_ADMIN_ROLE` and the block timestamp at which the
    ///         transfer becomes acceptable. Returns `(address(0), 0)` if no
    ///         transfer is scheduled.
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 acceptSchedule);

    /// @notice The current delay (in seconds) that applies to a default-admin
    ///         transfer or renunciation. A scheduled transfer becomes
    ///         acceptable `defaultAdminDelay()` seconds after `beginDefaultAdminTransfer`.
    function defaultAdminDelay() external view returns (uint48);

    /// @notice Returns the next scheduled delay value and the block timestamp
    ///         at which it takes effect. Returns `(0, 0)` if no delay change
    ///         is scheduled.
    function pendingDefaultAdminDelay() external view returns (uint48 newDelay, uint48 effectSchedule);

    /// @notice The minimum wait (in seconds) before a delay-INCREASE takes
    ///         effect. Delay decreases are subject to the current delay;
    ///         delay increases are subject to whichever is greater of the
    ///         current delay or this floor. Prevents an admin from defending
    ///         a key compromise by instantaneously extending the delay to
    ///         lock out the rightful owner.
    function defaultAdminDelayIncreaseWait() external view returns (uint48);

    /// @notice Schedules a transfer of `DEFAULT_ADMIN_ROLE` to `newAdmin`.
    ///         The transfer becomes acceptable `defaultAdminDelay()` seconds
    ///         after this call; until then `newAdmin` may call
    ///         `acceptDefaultAdminTransfer`. The current admin may
    ///         `cancelDefaultAdminTransfer` at any time before acceptance.
    /// @dev    Requires `DEFAULT_ADMIN_ROLE`. Setting `newAdmin == address(0)`
    ///         schedules a renunciation. Calling again replaces any prior
    ///         pending transfer with the new one (resets the delay clock).
    function beginDefaultAdminTransfer(address newAdmin) external;

    /// @notice Cancels any pending default-admin transfer. Requires
    ///         `DEFAULT_ADMIN_ROLE`. No-op if no transfer is pending.
    function cancelDefaultAdminTransfer() external;

    /// @notice Accepts the pending default-admin transfer. Caller MUST be
    ///         the address scheduled via `beginDefaultAdminTransfer`, and
    ///         the current `block.timestamp` must be at or after the
    ///         scheduled `acceptSchedule`. Atomically transfers
    ///         `DEFAULT_ADMIN_ROLE` from the previous admin to the caller.
    /// @dev    Reverts with `NoPendingDefaultAdmin` if no transfer is
    ///         pending, with `EnforcedDefaultAdminDelay` if called before
    ///         the schedule, or with `Unauthorized` if called by anyone
    ///         other than the pending admin.
    function acceptDefaultAdminTransfer() external;

    /// @notice Schedules a change to `defaultAdminDelay`. Requires
    ///         `DEFAULT_ADMIN_ROLE`. Decreases take effect after the
    ///         current delay elapses; increases take effect after the
    ///         greater of the current delay or `defaultAdminDelayIncreaseWait`.
    function changeDefaultAdminDelay(uint48 newDelay) external;

    /// @notice Cancels any pending delay change. Requires `DEFAULT_ADMIN_ROLE`.
    ///         No-op if no change is pending.
    function rollbackDefaultAdminDelay() external;

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether the contract is currently paused. While paused,
    ///         `transfer`, `transferFrom`, and their memo siblings revert
    ///         with `ContractPaused`. Mints, burns, role changes, policy
    ///         changes, and other admin actions are NOT blocked by pause.
    function paused() external view returns (bool);

    /// @notice Pauses the contract. Requires `PAUSABLE` capability and
    ///         `PAUSE_ROLE`. Reverts with `AlreadyPaused` if already paused.
    function pause() external;

    /// @notice Unpauses the contract. Requires `PAUSABLE` capability and
    ///         `UNPAUSE_ROLE`. Reverts with `NotPaused` if not currently
    ///         paused.
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                                 POLICY
    //////////////////////////////////////////////////////////////*/

    /// @notice The policy ID currently gating this token's transfers and mints.
    ///         Newly created tokens default to ID 1 (always-allow), which is
    ///         a no-op gate. Setting to ID 0 (always-reject) functions as a
    ///         soft pause that survives across `unpause`.
    function transferPolicyId() external view returns (uint64);

    /// @notice Sets a new transfer policy. Requires `POLICY_MUTABLE`
    ///         capability and `DEFAULT_ADMIN_ROLE`. The policy must exist in
    ///         the policy registry. Takes effect immediately for the next
    ///         transfer or mint.
    function changeTransferPolicyId(uint64 newPolicyId) external;

    /*//////////////////////////////////////////////////////////////
                              SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    /// @notice The maximum total supply enforced on `mint`. A value of
    ///         `type(uint256).max` indicates no cap (the default).
    function supplyCap() external view returns (uint256);

    /// @notice Sets a new supply cap. Requires `CAP_MUTABLE` capability and
    ///         `DEFAULT_ADMIN_ROLE`. Reverts with `InvalidSupplyCap` if the
    ///         new cap is below the current `totalSupply` (we never
    ///         invalidate already-issued supply).
    function setSupplyCap(uint256 newSupplyCap) external;

    /*//////////////////////////////////////////////////////////////
                       PERMIT (EIP-2612 + ERC-1271)
    //////////////////////////////////////////////////////////////*/

    /// @notice The current EIP-712 domain separator for this token. Computed
    ///         dynamically each call so it remains correct after a chain fork
    ///         that changes `block.chainid`.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The current permit nonce for `owner`. Incremented by exactly 1
    ///         on each successful `permit` of either form.
    function nonces(address owner) external view returns (uint256);

    /// @notice EIP-2612 canonical permit. Recovers `owner` via ECDSA from
    ///         `(v, r, s)`. Reverts with `PermitExpired` if `block.timestamp > deadline`,
    ///         or `InvalidSignature` if recovery does not yield `owner`.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Permit accepting a packed `signature` for either an EOA owner
    ///         or a contract owner.
    /// @dev    If `owner.code.length == 0`, treats `signature` as 65-byte
    ///         packed ECDSA (`abi.encodePacked(r, s, v)`). If
    ///         `owner.code.length > 0`, calls `IERC1271(owner).isValidSignature(digest, signature)`
    ///         and accepts iff the magic value `0x1626ba7e` is returned.
    ///         Same nonce, same digest, same `PermitExpired` semantics as the
    ///         canonical form.
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes calldata signature)
        external;

    /*//////////////////////////////////////////////////////////////
                          CONTRACT URI (ERC-7572)
    //////////////////////////////////////////////////////////////*/

    /// @notice An offchain URI pointing at contract-level metadata for this
    ///         token (ERC-7572).
    function contractURI() external view returns (string memory);

    /// @notice Updates `contractURI`. Requires `URI_MUTABLE` capability and
    ///         `DEFAULT_ADMIN_ROLE`. Emits the parameterless
    ///         `ContractURIUpdated` event per ERC-7572.
    function setContractURI(string calldata newURI) external;
}
