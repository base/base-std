// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IB20
/// @notice The protocol-enshrined precompile half of a Base-native ERC-20.
///         A B-20 token is an architectural pair: this precompile (which
///         owns balance state, raw transfer mechanics, the policy hook,
///         and the pause flag) and an EVM wrapper contract bound to it at
///         creation. The precompile is opinion-free; all governance, role
///         logic, and product-specific behavior live in the wrapper.
///
/// @dev    Backward-compatible with ERC-20 at the function-selector level:
///         `transfer`, `transferFrom`, `approve`, `balanceOf`, `allowance`,
///         `totalSupply`, `name`, `symbol`, `decimals` all match ERC-20
///         selectors and event signatures.
///
///         **Wrapper binding.** Each precompile is bound to exactly one
///         wrapper EVM contract at creation, retrievable via `wrapper()`.
///         The binding is immutable. The precompile's privileged
///         operations (`mint`, `burn`, `wrapperTransfer`, `setPaused`,
///         `setTransferPolicyId`) revert with `OnlyWrapper` for any other
///         caller. Wrapper upgradability, when needed, is achieved via
///         standard EVM proxy patterns inside the wrapper itself.
///
///         **Policy hook.** Every balance-mutating operation that moves
///         value (`transfer`, `transferFrom`, `mint`, `wrapperTransfer`)
///         passes through the policy registry referenced by
///         `transferPolicyId`. Burns are NOT policy-checked: they reduce
///         supply rather than move value to a recipient and are
///         deliberately available for compliance enforcement (sanctions
///         seizure).
///
///         **Gas payment is a transfer.** When this token is configured
///         as a gas asset, fee debits go through the same
///         `transferPolicyId` check as user-initiated transfers. A
///         sanctioned account that cannot transfer also cannot pay gas
///         in this token. A paused token cannot pay gas at all.
interface IB20 {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice The caller is not the bound wrapper. The privileged
    ///         operations on this precompile (mint, burn, wrapperTransfer,
    ///         setPaused, setTransferPolicyId) are callable only by the
    ///         wrapper EVM contract bound at creation.
    error OnlyWrapper();

    /// @notice The token is paused. Transfers, mints, burns, and
    ///         wrapperTransfers are all blocked while paused. `approve`
    ///         and the wrapper-only state setters remain available.
    error ContractPaused();

    /// @notice The owner does not have enough balance for the requested
    ///         transfer or burn.
    error InsufficientBalance(uint256 currentBalance, uint256 requestedAmount);

    /// @notice The spender does not have enough allowance for the
    ///         requested `transferFrom`.
    error InsufficientAllowance(uint256 currentAllowance, uint256 requestedAmount);

    /// @notice The active transfer policy denied the operation.
    ///         `policyId` is the ID currently set as `transferPolicyId`.
    error PolicyForbids(uint64 policyId);

    /// @notice The provided policy ID does not exist in the policy
    ///         registry.
    error InvalidPolicyId(uint64 policyId);

    /// @notice A required address argument was the zero address.
    error InvalidRecipient();

    /// @notice The amount argument was zero where a non-zero value is
    ///         required.
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-20 standard transfer event. Emitted on every
    ///         successful transfer (including `transferFrom` and
    ///         `wrapperTransfer`), mint (`from = address(0)`), and burn
    ///         (`to = address(0)`).
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice ERC-20 standard approval event.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @notice The token was paused.
    event Paused();

    /// @notice The token was unpaused.
    event Unpaused();

    /// @notice The transfer policy was changed. `oldPolicyId` and
    ///         `newPolicyId` are the policy IDs immediately before and
    ///         after the change.
    event TransferPolicyUpdated(uint64 oldPolicyId, uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                                ERC-20
    //////////////////////////////////////////////////////////////*/

    /// @notice Token name. Immutable, set at creation.
    function name() external view returns (string memory);

    /// @notice Token symbol. Immutable, set at creation.
    function symbol() external view returns (string memory);

    /// @notice Number of decimal places. Immutable, set at creation.
    function decimals() external view returns (uint8);

    /// @notice Total supply of the token.
    function totalSupply() external view returns (uint256);

    /// @notice Balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Allowance granted by `owner` to `spender`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Transfers `amount` from `msg.sender` to `to`. Reverts with
    ///         `ContractPaused` if paused, `PolicyForbids` if the active
    ///         transfer policy denies the transfer, `InsufficientBalance`
    ///         if `msg.sender` does not have enough balance, and
    ///         `InvalidRecipient` if `to == address(0)`.
    /// @dev    The same policy check applies to fee payment when this
    ///         token is configured as a gas asset.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers `amount` from `from` to `to` using `msg.sender`'s
    ///         allowance. Reverts as `transfer` does, plus
    ///         `InsufficientAllowance` if `msg.sender` does not have
    ///         enough allowance from `from`.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Sets `spender`'s allowance to `amount`. Not gated by the
    ///         transfer policy or by pause; only the act of MOVING
    ///         balance is gated.
    function approve(address spender, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                              STATE READS
    //////////////////////////////////////////////////////////////*/

    /// @notice The EVM wrapper contract bound to this precompile at
    ///         creation. Immutable. Holds exclusive authority to call
    ///         this precompile's privileged operations (`mint`, `burn`,
    ///         `wrapperTransfer`, `setPaused`, `setTransferPolicyId`).
    ///         If the wrapper needs to be upgraded post-creation, it
    ///         must use a proxy pattern internally; the precompile sees
    ///         this address forever.
    function wrapper() external view returns (address);

    /// @notice The policy ID currently gating this token's transfers,
    ///         mints, and wrapperTransfers. Resolved via the canonical
    ///         policy registry precompile. ID `0` always rejects
    ///         (functional soft-pause via policy); ID `1` always allows.
    function transferPolicyId() external view returns (uint64);

    /// @notice Whether the token is currently paused. While paused,
    ///         `transfer`, `transferFrom`, `mint`, `burn`, and
    ///         `wrapperTransfer` revert with `ContractPaused`. `approve`
    ///         and the wrapper-only state setters remain available so
    ///         the wrapper can prepare state changes while the token is
    ///         halted.
    function paused() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          WRAPPER-ONLY OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amount` to `to`. Caller MUST be the bound
    ///         `wrapper`. Subject to the transfer policy:
    ///         `isAuthorizedMintRecipient(to)` must hold. Blocked by
    ///         pause. Emits `Transfer(address(0), to, amount)`.
    function mint(address to, uint256 amount) external;

    /// @notice Burns `amount` from `from`. Caller MUST be the bound
    ///         `wrapper`. NOT subject to the transfer policy: burns
    ///         reduce supply rather than move value to a recipient and
    ///         are deliberately available for compliance enforcement
    ///         (e.g. seizure of sanctioned balances). Blocked by pause.
    ///         Emits `Transfer(from, address(0), amount)`.
    function burn(address from, uint256 amount) external;

    /// @notice Transfers `amount` from `from` to `to` WITHOUT consulting
    ///         the precompile-level allowance. Caller MUST be the bound
    ///         `wrapper`. Subject to the transfer policy and to pause,
    ///         identical to `transfer` and `transferFrom` in those
    ///         respects. Emits `Transfer(from, to, amount)`.
    /// @dev    The escape hatch for wrapper-mediated authorization
    ///         flows: EIP-2612 permit, ERC-3009 transfer with
    ///         authorization, signature-based payment intents, etc.
    ///         The wrapper verifies user authorization off-chain
    ///         (typically via signature recovery) and is trusted to
    ///         only call this when the user has actually authorized the
    ///         transfer. The precompile-level allowance from `from` is
    ///         irrelevant; the wrapper IS the authorization.
    function wrapperTransfer(address from, address to, uint256 amount) external returns (bool);

    /// @notice Sets the paused state. Caller MUST be the bound
    ///         `wrapper`. Idempotent: calling with the current value is
    ///         a no-op and does not emit an event. Calling with a new
    ///         value emits `Paused()` or `Unpaused()` accordingly.
    function setPaused(bool isPaused) external;

    /// @notice Sets a new transfer policy. Caller MUST be the bound
    ///         `wrapper`. The policy MUST exist in the policy registry
    ///         (or be one of the built-in IDs `0` or `1`). Takes effect
    ///         immediately for the next transfer or mint.
    function setTransferPolicyId(uint64 newPolicyId) external;
}
