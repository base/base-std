// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title ITokenFactory
/// @notice Singleton factory for creating B-20 tokens of any variant.
///         A single precompile at a fixed address exposes three creation
///         methods (`createDefault`, `createStablecoin`, `createSecurity`).
///         Creation is permissionless: anyone may create a token of any
///         variant, and the creator picks the initial admin.
///
/// @dev    Each token is deployed at a deterministic address derived from
///         `(variant, creator, salt)`. The variant is encoded in the
///         address prefix, so the variant of any address is recoverable
///         via `variantOf` without a storage lookup. Address prediction
///         functions (`predict*Address`) let callers compute the address
///         off-chain or pre-fund the address before deployment.
///
///         The factory is a precompile and has no admin or governance.
///         Each created token has its own independent admin and operates
///         per the inherited `IDefaultToken` (and variant) surface.
interface ITokenFactory {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Variant of a B-20 token. Recoverable from the token's
    ///         address prefix; `NONE` indicates the address is not a B-20
    ///         token created by this factory.
    enum TokenVariant {
        NONE,
        DEFAULT,
        STABLECOIN,
        SECURITY
    }

    /// @notice Creation parameters for a Default-variant token.
    /// @param name                   ERC-20 token name.
    /// @param symbol                 ERC-20 token symbol.
    /// @param decimals               ERC-20 token decimals (issuer choice).
    /// @param admin                  Initial holder of `DEFAULT_ADMIN_ROLE`.
    /// @param defaultAdminDelay      Initial value for the two-step admin
    ///                               transfer delay (seconds). Zero means
    ///                               transfers are effectively single-step
    ///                               at creation; admin can raise via
    ///                               `changeDefaultAdminDelay` later.
    /// @param capabilities           Immutable capability bitfield.
    /// @param initialSupply          Amount minted atomically at creation.
    ///                               Bypasses the transfer-policy check
    ///                               and the `MINTABLE` capability gate
    ///                               (this is the bootstrap mint, not a
    ///                               normal mint operation).
    /// @param initialSupplyRecipient Address that receives `initialSupply`.
    ///                               Ignored when `initialSupply == 0`.
    /// @param transferPolicyId       Initial value of `transferPolicyId`.
    ///                               Must reference an existing policy in
    ///                               the policy registry.
    /// @param supplyCap              Initial value of `supplyCap`. Use
    ///                               `type(uint256).max` for no cap.
    /// @param contractURI            Initial ERC-7572 contract URI.
    /// @param salt                   Caller-chosen salt for deterministic
    ///                               address derivation.
    struct CreateDefaultTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        uint48 defaultAdminDelay;
        uint256 capabilities;
        uint256 initialSupply;
        address initialSupplyRecipient;
        uint64 transferPolicyId;
        uint256 supplyCap;
        string contractURI;
        bytes32 salt;
    }

    /// @notice Creation parameters for a Stablecoin-variant token.
    /// @param currency               Immutable currency identifier (e.g.
    ///                               "USD", "EUR", "XAU"). See `IStablecoin.currency`
    ///                               for the convention.
    /// @dev    All other fields have the same semantics as the Default
    ///         params struct.
    struct CreateStablecoinParams {
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        uint48 defaultAdminDelay;
        uint256 capabilities;
        uint256 initialSupply;
        address initialSupplyRecipient;
        uint64 transferPolicyId;
        uint256 supplyCap;
        string contractURI;
        string currency;
        bytes32 salt;
    }

    /// @notice Creation parameters for a Security-variant token.
    /// @param redeemPolicyId          Initial value of `redeemPolicyId`.
    ///                                Typically a simple WHITELIST policy
    ///                                whose admin is the brokerage-onboarding
    ///                                operator. Defaulting to policy ID 0
    ///                                (always-reject) is the safe choice
    ///                                if no allowlist is ready at creation.
    /// @param minimumRedeemable       Initial minimum redeem amount.
    /// @param shareRatioNumerator     Initial share-ratio numerator. Must
    ///                                be non-zero. Use `1` for 1:1 unless
    ///                                the issuer wants headroom for
    ///                                fractional ratio updates.
    /// @param shareRatioDenominator   Initial share-ratio denominator.
    ///                                Must be non-zero.
    /// @param securityIdentifiers     Initial `[type, value]` pairs (e.g.
    ///                                `[["isin", "US..."], ["cusip", "..."]]`).
    ///                                May be empty; identifiers can be
    ///                                added later via
    ///                                `updateSecurityIdentifier`.
    /// @dev    Security tokens have NO `initialSupply` parameter. All
    ///         issuance goes through `create` (rate-limited compliant
    ///         path) or `adminMint` (cold-path batch with announcement
    ///         coupling) after creation. The supply cap is set at
    ///         creation; `transferPolicyId` and `redeemPolicyId` must
    ///         reference existing policies.
    struct CreateSecurityTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        uint48 defaultAdminDelay;
        uint256 capabilities;
        uint64 transferPolicyId;
        uint64 redeemPolicyId;
        uint256 minimumRedeemable;
        uint48 shareRatioNumerator;
        uint48 shareRatioDenominator;
        string[2][] securityIdentifiers;
        uint256 supplyCap;
        string contractURI;
        bytes32 salt;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice A token already exists at the deterministic address derived
    ///         from `(variant, msg.sender, salt)`. Caller must use a
    ///         different salt.
    error TokenAlreadyExists(address token);

    /// @notice The provided policy ID does not exist in the policy registry.
    error InvalidPolicyId(uint64 policyId);

    /// @notice The provided share-ratio numerator or denominator is zero.
    error InvalidShareRatio();

    /// @notice The provided decimals value is outside the allowed range
    ///         (implementation-defined; typically 0..18 inclusive).
    error InvalidDecimals(uint8 decimals);

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /// @notice The provided supply cap is below the configured initial
    ///         supply, or is otherwise invalid.
    error InvalidSupplyCap();

    /// @notice A security identifier `type` was the empty string. Identifier
    ///         types must be non-empty (typical values: "isin", "cusip",
    ///         "figi", "sedol").
    error EmptyIdentifierType();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a Default-variant token is created.
    event DefaultTokenCreated(
        address indexed token,
        address indexed creator,
        address indexed admin,
        string name,
        string symbol,
        uint8 decimals,
        uint256 capabilities,
        uint256 initialSupply,
        bytes32 salt
    );

    /// @notice Emitted when a Stablecoin-variant token is created.
    event StablecoinCreated(
        address indexed token,
        address indexed creator,
        address indexed admin,
        string name,
        string symbol,
        uint8 decimals,
        string currency,
        uint256 capabilities,
        uint256 initialSupply,
        bytes32 salt
    );

    /// @notice Emitted when a Security-variant token is created.
    event SecurityTokenCreated(
        address indexed token,
        address indexed creator,
        address indexed admin,
        string name,
        string symbol,
        uint8 decimals,
        uint256 capabilities,
        uint48 shareRatioNumerator,
        uint48 shareRatioDenominator,
        bytes32 salt
    );

    /*//////////////////////////////////////////////////////////////
                            CREATION METHODS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a Default-variant token at a deterministic address
    ///         derived from `(DEFAULT, msg.sender, params.salt)`. Mints
    ///         `params.initialSupply` to `params.initialSupplyRecipient`
    ///         atomically (bypasses the policy check and `MINTABLE` gate;
    ///         this is the bootstrap mint).
    /// @return token The address of the newly created token.
    function createDefault(CreateDefaultTokenParams calldata params) external returns (address token);

    /// @notice Creates a Stablecoin-variant token at a deterministic
    ///         address derived from `(STABLECOIN, msg.sender, params.salt)`.
    ///         Mints `params.initialSupply` to
    ///         `params.initialSupplyRecipient` atomically. Sets the
    ///         immutable `currency` field.
    function createStablecoin(CreateStablecoinParams calldata params) external returns (address token);

    /// @notice Creates a Security-variant token at a deterministic address
    ///         derived from `(SECURITY, msg.sender, params.salt)`. NO
    ///         initial supply is minted; security tokens use `create` /
    ///         `adminMint` for issuance after deployment.
    function createSecurity(CreateSecurityTokenParams calldata params) external returns (address token);

    /*//////////////////////////////////////////////////////////////
                          ADDRESS PREDICTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deterministic address that `createDefault` would
    ///         assign for the given `(creator, salt)`. The address depends
    ///         only on the variant, creator, and salt — not on any of the
    ///         other creation parameters. Stable across all parameter
    ///         choices for a given `(creator, salt)`.
    function predictDefaultAddress(address creator, bytes32 salt) external view returns (address);

    /// @notice Same as `predictDefaultAddress`, for the Stablecoin variant.
    function predictStablecoinAddress(address creator, bytes32 salt) external view returns (address);

    /// @notice Same as `predictDefaultAddress`, for the Security variant.
    function predictSecurityAddress(address creator, bytes32 salt) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                         VARIANT INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the variant of `token`. Returns `NONE` if `token`
    ///         is not a B-20 token created by this factory. Recovered
    ///         from the address prefix; no storage read.
    function variantOf(address token) external view returns (TokenVariant);

    /// @notice Convenience: `variantOf(token) != NONE`.
    function isB20(address token) external view returns (bool);
}
