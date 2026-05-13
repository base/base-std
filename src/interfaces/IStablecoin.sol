// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IDefaultToken} from "./IDefaultToken.sol";

/// @title IStablecoin
/// @notice A B-20 token variant for value-pegged tokens (USD, EUR, XAU, etc.).
///         Inherits the full IDefaultToken surface and adds three things
///         specific to stablecoin issuance and payment use cases:
///
///         1. An immutable `currency()` identifier for routing, categorization,
///            and wallet display.
///         2. Per-minter rate limiting (rolling capacity per minter address)
///            for risk management and multi-party governance.
///         3. ERC-3009 transfer-with-authorization for gasless and
///            front-run-resistant transfers (USDC-parity payment surface).
///
/// @dev    Stablecoin compliance (sanctions, jurisdiction restrictions,
///         blocklisting) is delegated to the policy engine via IDefaultToken's
///         `transferPolicyId`, not implemented here. Issuers point their
///         stablecoin at a compound policy with the appropriate sender,
///         recipient, and mint-recipient rules.
///
///         The "freeze, never seize" philosophy (CDP Custom Stablecoin) vs.
///         the "force-burn for sanctions" philosophy (Tangor) is expressed
///         via the `BURN_BLOCKED` capability bit. Stablecoin issuers default
///         to freeze; can opt into seize by enabling `BURN_BLOCKED` at
///         creation.
interface IStablecoin is IDefaultToken {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MintRateLimitNotConfigured(address minter);
    error MintRateLimitExceeded(address minter, uint256 amount, uint256 remaining);
    error InvalidRateLimitConfig();

    error AuthorizationAlreadyUsed(address authorizer, bytes32 nonce);
    error AuthorizationNotYetValid(uint256 validAfter);
    error AuthorizationExpired(uint256 validBefore);
    error CallerMustBePayee(address caller, address payee);
    error InvalidAuthorization();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event MintRateLimitConfigured(address indexed minter, uint256 limit, uint40 interval);
    event MintRateLimitRemoved(address indexed minter);
    event MintRateLimitConsumed(address indexed minter, uint256 amount, uint256 remaining);

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /*//////////////////////////////////////////////////////////////
                            ROLE IDENTIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Required to call `configureMinter` and `removeMinterRateLimit`.
    ///         Held separately from `MINT_ROLE` so the authority that grants
    ///         minting rights (typically `DEFAULT_ADMIN_ROLE`) can be
    ///         distinct from the authority that tunes per-minter quotas.
    function MINT_RATE_LIMIT_ROLE() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          CURRENCY IDENTIFIER
    //////////////////////////////////////////////////////////////*/

    /// @notice The reference asset this stablecoin is designed to track. Set
    ///         at creation by the factory; immutable thereafter.
    /// @dev    Two stablecoins tracking the same asset return the same
    ///         identifier. Conventions:
    ///         - ISO-4217 codes for fiat / commodity references: "USD",
    ///           "EUR", "JPY", "XAU" (gold), "XAG" (silver).
    ///         - Symbol for non-ISO references: "BTC", "ETH" (for tokens
    ///           tracking the price of those assets).
    ///         - The token's own symbol if it tracks no external reference
    ///           (governance, utility tokens that nonetheless want the
    ///           stablecoin variant for the operational surface).
    function currency() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                       PER-MINTER RATE LIMITING
    //////////////////////////////////////////////////////////////*/

    /// @notice Configures or replaces the rate-limit for an existing minter.
    ///         The minter MUST already hold `MINT_ROLE`. Setting a new limit
    ///         RESETS the remaining capacity to the full `limit`.
    /// @dev    Requires `STABLECOIN_MINT_RATE_LIMITED` capability and
    ///         `MINT_RATE_LIMIT_ROLE`. Reverts with `InvalidRateLimitConfig`
    ///         if `limit == 0` or `interval == 0`. Reverts with
    ///         `Unauthorized` if `minter` does not hold `MINT_ROLE`.
    function configureMinter(address minter, uint216 limit, uint40 interval) external;

    /// @notice Atomically grants `MINT_ROLE` to `minter` and configures their
    ///         rate-limit in a single transaction. Eliminates the race where
    ///         a freshly-granted minter has the role but no rate-limit
    ///         configured yet (and therefore reverts on first mint).
    /// @dev    Requires `STABLECOIN_MINT_RATE_LIMITED` capability and
    ///         `DEFAULT_ADMIN_ROLE` (since it grants a role).
    function grantMinterRoleWithLimit(address minter, uint216 limit, uint40 interval) external;

    /// @notice Removes a minter's rate-limit configuration without revoking
    ///         their `MINT_ROLE`. Subsequent `mint` calls by `minter` will
    ///         revert with `MintRateLimitNotConfigured` until configured
    ///         again.
    /// @dev    Requires `STABLECOIN_MINT_RATE_LIMITED` capability and
    ///         `MINT_RATE_LIMIT_ROLE`. Implementations SHOULD also clear
    ///         the rate-limit automatically when `MINT_ROLE` is revoked
    ///         from a minter via `revokeRole`.
    function removeMinterRateLimit(address minter) external;

    /// @notice Returns the current available mint capacity for `minter` at
    ///         the current block timestamp, accounting for elapsed time
    ///         since the last consumption.
    /// @dev    Reverts with `MintRateLimitNotConfigured` if `minter` has no
    ///         active rate-limit configuration.
    function currentMintLimit(address minter) external view returns (uint256);

    /// @notice Returns the configured `(limit, interval)` for `minter`.
    ///         Returns `(0, 0)` if `minter` has no active configuration.
    function mintRateLimitConfig(address minter) external view returns (uint216 limit, uint40 interval);

    /*//////////////////////////////////////////////////////////////
                       ERC-3009 AUTHORIZATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 typehash for `transferWithAuthorization`. Computed as
    ///         keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    function TRANSFER_WITH_AUTHORIZATION_TYPEHASH() external view returns (bytes32);

    /// @notice EIP-712 typehash for `receiveWithAuthorization`. Computed as
    ///         keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    function RECEIVE_WITH_AUTHORIZATION_TYPEHASH() external view returns (bytes32);

    /// @notice EIP-712 typehash for `cancelAuthorization`. Computed as
    ///         keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    function CANCEL_AUTHORIZATION_TYPEHASH() external view returns (bytes32);

    /// @notice Whether `nonce` for `authorizer` has been consumed (via use or
    ///         cancellation). ERC-3009 nonces are 32-byte random values, NOT
    ///         sequential, so multiple authorizations can be in flight
    ///         concurrently and consumed independently.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool used);

    /// @notice Executes a transfer from `from` to `to` using a signed
    ///         authorization. Anyone may submit. The transfer is subject to
    ///         the active transfer policy and pause state, same as a normal
    ///         `transfer`.
    /// @dev    Requires `STABLECOIN_AUTHORIZATIONS` capability. Reverts with
    ///         `AuthorizationNotYetValid` if `block.timestamp <= validAfter`,
    ///         `AuthorizationExpired` if `block.timestamp >= validBefore`,
    ///         `AuthorizationAlreadyUsed` on nonce reuse, and
    ///         `InvalidAuthorization` on signature recovery failure. The
    ///         `(v, r, s)` form is the canonical ECDSA path; the `bytes`
    ///         overload accepts either ECDSA OR ERC-1271 contract sigs.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Same as `transferWithAuthorization` (canonical ECDSA), but
    ///         the caller MUST be `to`. Prevents front-running by ensuring
    ///         only the intended payee can submit. Useful when the payer
    ///         signs for a specific recipient and wants no relayer to be
    ///         able to redirect.
    /// @dev    Reverts with `CallerMustBePayee` if `msg.sender != to`.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Cancels a previously-signed authorization nonce so it cannot
    ///         be used. The cancellation is itself a signed message; anyone
    ///         may submit. Reverts with `AuthorizationAlreadyUsed` if the
    ///         nonce has already been used or canceled.
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice `transferWithAuthorization` accepting either an ECDSA
    ///         (65-byte packed `(r, s, v)`) signature for EOA authorizers or
    ///         an ERC-1271 signature for contract authorizers. Validity is
    ///         determined by whether `from.code.length > 0`.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;

    /// @notice `receiveWithAuthorization` accepting either an ECDSA or
    ///         ERC-1271 signature. See the canonical `receiveWithAuthorization`
    ///         for the front-run-resistance constraint.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;

    /// @notice `cancelAuthorization` accepting either an ECDSA or ERC-1271
    ///         signature.
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes calldata signature) external;
}
