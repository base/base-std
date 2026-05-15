// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title ITokenFactory
/// @notice Singleton factory precompile for creating B-20 tokens. Exposes
///         three creation methods, one per variant the caller wants:
///         `createDefault`, `createStablecoin`, `createSecurity`. Each
///         returns the address of the newly created token, deployed at
///         a deterministic location derived from the caller's salt.
///
/// @dev    **Variants and address prefixes.** Two address prefixes are
///         reserved at the chain-config level for B-20 tokens:
///
///             - `0xB200...` for Default and Stablecoin tokens
///             - `0xB201...` for Security tokens
///
///         Default and Stablecoin share the same prefix because a
///         Stablecoin is structurally a Default token with `currency`
///         set; the only difference is whether the immutable `currency()`
///         field returns a non-empty string. Tools that need to
///         distinguish them post-creation call `currency()` (returns
///         empty string for non-stablecoin Default tokens) or use the
///         `isStablecoin` convenience view.
///
///         Security tokens use a distinct prefix because they implement
///         the broader `ISecurityToken` surface (announcements, share
///         ratio, create / adminMint / adminBurn, security identifiers).
///         The chain-internal precompile dispatch differs for B201
///         tokens.
///
///         **Variant introspection.** `variantOf(token)` returns the
///         variant from the address prefix alone, with no storage read.
///         Returns `DEFAULT` for any `0xB200...` token and `SECURITY` for
///         any `0xB201...` token. There is no `STABLECOIN` enum value
///         because Stablecoin and Default share the prefix; use
///         `isStablecoin(token)` to detect the stablecoin sub-case.
///
///         **Address determinism.** Each `predict*Address` view returns
///         the deterministic address that the matching `create*` call
///         would assign for a given `(creator, salt)`. Addresses depend
///         only on the variant, the creator, and the salt — not on any
///         other creation parameters — so callers can compute the
///         address off-chain or pre-fund it before deployment. Default
///         and Stablecoin share the same derivation: `predictDefaultAddress`
///         and `predictStablecoinAddress` return the SAME address for
///         the same `(creator, salt)`. The caller picks which to create
///         at that address; only one (Default OR Stablecoin) can occupy
///         a given `(creator, salt)` slot.
///
///         **Permissionless.** Anyone may create a token of any variant.
///         The factory has no admin and no per-call gating beyond the
///         standard creator-pays-gas flow. Spam at the address-space
///         level is bounded by gas costs and the `(creator, salt)`
///         deterministic derivation.
///
///         **Each token is independent.** The factory creates the token
///         and bootstrap-mints initial supply (for Default and
///         Stablecoin) atomically, then the token is fully self-governing.
///         The factory has no ongoing relationship with any token it
///         created. Issuers who need wrappers / controllers (Bridge's
///         TIP20Controller pattern, CCS's beacon proxy) deploy those
///         separately as normal EVM contracts.
interface ITokenFactory {
    /*//////////////////////////////////////////////////////////////
                          ADDRESS PREFIXES
    //////////////////////////////////////////////////////////////*/

    /// @notice The first two bytes of any Default or Stablecoin token's
    ///         address. Reserved at the chain-config level for B-20
    ///         tokens of those variants.
    function DEFAULT_ADDRESS_PREFIX() external view returns (bytes2);

    /// @notice The first two bytes of any Security token's address.
    ///         Reserved at the chain-config level for B-20 security
    ///         tokens.
    function SECURITY_ADDRESS_PREFIX() external view returns (bytes2);

    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Variant of a B-20 token. Recoverable from the token's
    ///         address prefix; `NONE` indicates the address is not a
    ///         B-20 token created by this factory.
    /// @dev    Stablecoin is NOT a separate variant value: Stablecoin
    ///         and Default tokens share the `DEFAULT` enum value AND
    ///         the same address prefix, distinguished only by whether
    ///         `currency()` returns a non-empty string. Use the
    ///         `isStablecoin(token)` convenience view to identify the
    ///         stablecoin sub-case.
    enum TokenVariant {
        NONE,
        DEFAULT,
        SECURITY
    }

    /// @notice Creation parameters for a Default-variant token.
    /// @param name                   ERC-20 token name. Mutable post-
    ///                               creation via `setName`.
    /// @param symbol                 ERC-20 token symbol. Mutable post-
    ///                               creation via `setSymbol`.
    /// @param decimals               Number of decimal places. Immutable.
    ///                               Per-token custom; the factory does
    ///                               not enforce a fixed value.
    /// @param admin                  Initial holder of `DEFAULT_ADMIN_ROLE`.
    ///                               Pass `address(0)` to create an
    ///                               ADMIN-LESS token (credibly neutral,
    ///                               no future role grants possible, no
    ///                               policy or pause changes possible).
    ///                               This is the "demonstrate no owner"
    ///                               case from the PRD; the
    ///                               last-admin-renounce guard does not
    ///                               apply because there was never an
    ///                               admin to renounce.
    /// @param capabilities           Immutable capability bitfield. See
    ///                               `Capabilities` for the bit
    ///                               definitions. Currently only
    ///                               `PAUSABLE` and `CAP_MUTABLE` are
    ///                               valid for Default-variant tokens.
    /// @param transferPolicyId       Initial value of `transferPolicyId`.
    ///                               OPEN DESIGN QUESTION: should this
    ///                               be required, or optional with a
    ///                               default of policy ID `1` (always-
    ///                               allow)? Currently required to force
    ///                               issuers to make an explicit
    ///                               compliance choice at creation. If
    ///                               policy ID `0` (always-reject) is
    ///                               passed, the token cannot transfer
    ///                               or mint until `changeTransferPolicyId`
    ///                               is called.
    /// @param supplyCap              Initial value of `supplyCap`. Use
    ///                               `type(uint256).max` for no cap.
    ///                               To make the token permanently
    ///                               fixed-supply, set this equal to
    ///                               `initialSupply` and leave
    ///                               `CAP_MUTABLE` unset.
    /// @param initialSupply          Amount minted atomically at
    ///                               creation. Set to `0` for no
    ///                               bootstrap mint.
    ///                               OPEN DESIGN QUESTION: bootstrap
    ///                               mints currently BYPASS the policy
    ///                               check (the policy may not be
    ///                               configured at creation). Worth
    ///                               revisiting whether issuers should
    ///                               be required to satisfy the policy
    ///                               at bootstrap; pro: tighter
    ///                               consistency, con: requires the
    ///                               policy to be created BEFORE the
    ///                               token, which is awkward.
    /// @param initialSupplyRecipient Address that receives `initialSupply`.
    ///                               Ignored when `initialSupply == 0`.
    /// @param minimumRedeemable      Initial value of `minimumRedeemable`.
    ///                               Use `0` to allow any non-zero
    ///                               redeem amount (typical for tokens
    ///                               without a redemption product).
    ///                               Mutable post-creation.
    /// @param contractURI            Initial ERC-7572 contract URI.
    ///                               Mutable post-creation by admin.
    /// @param salt                   Caller-chosen salt for deterministic
    ///                               address derivation.
    struct CreateDefaultTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        uint256 capabilities;
        uint64 transferPolicyId;
        uint256 supplyCap;
        uint256 initialSupply;
        address initialSupplyRecipient;
        uint256 minimumRedeemable;
        string contractURI;
        bytes32 salt;
    }

    /// @notice Creation parameters for a Stablecoin-variant token.
    /// @param currency               Immutable currency identifier
    ///                               (e.g. "USD", "EUR", "XAU"). See
    ///                               `IStablecoin.currency` for the
    ///                               convention. MUST be non-empty;
    ///                               passing an empty string defeats
    ///                               the point of using
    ///                               `createStablecoin` over
    ///                               `createDefault`.
    /// @dev    All other fields have the same semantics as the Default
    ///         params struct. Stablecoin tokens share the same address
    ///         prefix and address derivation as Default tokens; for a
    ///         given `(creator, salt)` pair, exactly ONE of `createDefault`
    ///         or `createStablecoin` can succeed (the other reverts
    ///         with `TokenAlreadyExists`).
    struct CreateStablecoinParams {
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        uint256 capabilities;
        uint64 transferPolicyId;
        uint256 supplyCap;
        uint256 initialSupply;
        address initialSupplyRecipient;
        uint256 minimumRedeemable;
        string contractURI;
        string currency;
        bytes32 salt;
    }

    /// @notice Creation parameters for a Security-variant token.
    /// @param shareRatioNumerator     Initial share-ratio numerator.
    ///                                Must be non-zero. Use `1` for 1:1
    ///                                unless the issuer wants headroom
    ///                                for fractional ratio updates.
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
    ///         creation; `transferPolicyId` must reference an existing
    ///         compound policy in the registry whose redeemer slot
    ///         encodes the brokerage allowlist (typically a Coinbase-
    ///         managed whitelist of KYC'd, brokerage-connected
    ///         accounts).
    ///
    ///         Security tokens use a distinct address prefix (`0xB201`)
    ///         from Default and Stablecoin tokens (`0xB200`). The
    ///         chain-internal precompile dispatch differs because
    ///         Security tokens implement the broader `ISecurityToken`
    ///         surface.
    ///
    ///         All other fields have the same semantics as the Default
    ///         params struct. Stablecoin-and-Default fields like
    ///         `initialSupplyRecipient` are absent here because Security
    ///         has no bootstrap mint.
    struct CreateSecurityTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        address admin;
        uint256 capabilities;
        uint64 transferPolicyId;
        uint256 supplyCap;
        uint256 minimumRedeemable;
        uint48 shareRatioNumerator;
        uint48 shareRatioDenominator;
        string[2][] securityIdentifiers;
        string contractURI;
        bytes32 salt;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice A token already exists at the deterministic address
    ///         derived from the caller's salt. Use a different salt.
    error TokenAlreadyExists(address token);

    /// @notice The provided policy ID does not exist in the policy
    ///         registry.
    error InvalidPolicyId(uint64 policyId);

    /// @notice The provided share-ratio numerator or denominator is
    ///         zero.
    error InvalidShareRatio();

    /// @notice The provided decimals value is outside the allowed
    ///         range (implementation-defined; typically 0..18
    ///         inclusive).
    error InvalidDecimals(uint8 decimals);

    /// @notice A required address argument was the zero address.
    ///         (NOTE: `admin == address(0)` is explicitly ALLOWED for
    ///         creating admin-less tokens; this error fires for other
    ///         positional zero-address checks like
    ///         `initialSupplyRecipient` when `initialSupply > 0`.)
    error ZeroAddress();

    /// @notice The provided supply cap is below the configured initial
    ///         supply, or is otherwise invalid.
    error InvalidSupplyCap();

    /// @notice The provided capability bitfield contains bits that are
    ///         not valid for this variant (e.g. setting a security-
    ///         specific bit on a Default token).
    error InvalidCapabilities(uint256 capabilities);

    /// @notice A security identifier `type` was the empty string.
    ///         Identifier types must be non-empty (typical values:
    ///         "isin", "cusip", "figi", "sedol").
    error EmptyIdentifierType();

    /// @notice `createStablecoin` was called with an empty `currency`
    ///         string. Use `createDefault` for tokens without a
    ///         currency identifier.
    error EmptyCurrency();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a Default-variant token is created (via
    ///         `createDefault`; tokens created via `createStablecoin`
    ///         emit `StablecoinCreated` instead).
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

    /// @notice Emitted when a Stablecoin-variant token is created (via
    ///         `createStablecoin`).
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

    /// @notice Creates a Default-variant token at the deterministic
    ///         address derived from `(DEFAULT prefix, msg.sender, params.salt)`.
    ///         If `params.initialSupply > 0`, mints that amount to
    ///         `params.initialSupplyRecipient` atomically as a
    ///         bootstrap operation.
    /// @dev    The bootstrap mint BYPASSES the transfer policy check
    ///         (the policy referenced by `params.transferPolicyId` may
    ///         legitimately not authorize the recipient yet at creation
    ///         time). Subsequent mints go through the normal policy
    ///         hook. **Open design question**: should the bootstrap
    ///         mint instead require the policy to authorize the
    ///         recipient?
    ///
    ///         If `params.admin == address(0)`, the token is created
    ///         with NO admin (the "demonstrate no owner" case from the
    ///         PRD): no role grants, policy changes, or pauses are
    ///         possible after creation. The last-admin-renounce guard
    ///         in `IDefaultToken.renounceRole` does not apply because
    ///         there was never an admin to renounce.
    /// @return token The address of the newly created token.
    function createDefault(CreateDefaultTokenParams calldata params) external returns (address token);

    /// @notice Creates a Stablecoin-variant token at the deterministic
    ///         address derived from `(DEFAULT prefix, msg.sender, params.salt)`.
    ///         Identical to `createDefault` except that
    ///         `IStablecoin.currency()` returns `params.currency`
    ///         (immutable). The address space is shared with
    ///         `createDefault`, so each `(creator, salt)` pair maps to
    ///         exactly one token (Default OR Stablecoin, not both).
    /// @dev    Reverts with `EmptyCurrency` if `params.currency` is
    ///         empty (use `createDefault` for tokens without a
    ///         currency identifier).
    function createStablecoin(CreateStablecoinParams calldata params) external returns (address token);

    /// @notice Creates a Security-variant token at the deterministic
    ///         address derived from `(SECURITY prefix, msg.sender, params.salt)`.
    ///         No bootstrap mint; security tokens use `create`
    ///         (rate-limited compliant issuance) or `adminMint`
    ///         (cold-path batch with announcement coupling) for
    ///         issuance after deployment.
    /// @dev    Security tokens use a distinct address prefix from
    ///         Default and Stablecoin tokens; addresses created via
    ///         `createSecurity` will never collide with addresses
    ///         created via `createDefault` or `createStablecoin`, even
    ///         for the same `(creator, salt)` pair.
    function createSecurity(CreateSecurityTokenParams calldata params) external returns (address token);

    /*//////////////////////////////////////////////////////////////
                          ADDRESS PREDICTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deterministic address that `createDefault`
    ///         would assign for the given `(creator, salt)`. Depends
    ///         only on the variant prefix, creator, and salt; not on
    ///         any of the other creation parameters.
    /// @dev    Returns the SAME address as `predictStablecoinAddress`
    ///         for the same `(creator, salt)` pair, because Default
    ///         and Stablecoin share the address space. Callers who
    ///         want both a Default and a Stablecoin token must use
    ///         different salts.
    function predictDefaultAddress(address creator, bytes32 salt) external view returns (address);

    /// @notice Returns the deterministic address that `createStablecoin`
    ///         would assign. Same as `predictDefaultAddress` for the
    ///         same `(creator, salt)` pair.
    function predictStablecoinAddress(address creator, bytes32 salt) external view returns (address);

    /// @notice Returns the deterministic address that `createSecurity`
    ///         would assign. Distinct from `predictDefaultAddress` /
    ///         `predictStablecoinAddress` because Security uses a
    ///         different address prefix.
    function predictSecurityAddress(address creator, bytes32 salt) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                         VARIANT INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the variant of `token`. Returns `NONE` if
    ///         `token` is not a B-20 token (i.e. address does not
    ///         start with a reserved B-20 prefix). Recovered from the
    ///         address prefix; no storage read.
    /// @dev    Returns `DEFAULT` for any token created via
    ///         `createDefault` OR `createStablecoin` (they share the
    ///         prefix). To distinguish the stablecoin sub-case, use
    ///         `isStablecoin(token)`.
    function variantOf(address token) external view returns (TokenVariant);

    /// @notice Convenience: `variantOf(token) != NONE`.
    function isB20(address token) external view returns (bool);

    /// @notice Convenience: returns true if `token` is a B-20 token AND
    ///         its `currency()` accessor returns a non-empty string,
    ///         indicating it was created via `createStablecoin` rather
    ///         than `createDefault`. Returns false for non-B-20
    ///         addresses, for Security tokens (no `currency` accessor),
    ///         and for Default tokens with empty `currency`.
    /// @dev    Reads from the token's storage (one external call).
    function isStablecoin(address token) external view returns (bool);
}

// ============================================================================
//                            DESIGN NOTES
// ============================================================================
//
// Open questions flagged inline in the NatSpec above, summarized:
//
// 1. Should `transferPolicyId` be required at creation, or optional with a
//    default (e.g. always-allow)? Currently required to force an explicit
//    compliance choice. Tradeoff: more friction for memecoins / simple
//    tokens that don't need compliance.
//
// 2. Should the bootstrap mint at creation BYPASS the transfer policy
//    check (current draft) or APPLY it? Bypass is convenient (the policy
//    may not be configured yet), but creates a foot-gun where the issuer
//    could mint to themselves under a permissive bootstrap and then
//    discover the policy doesn't authorize them post-creation.
//
// 3. Should we eventually add a two-step "renounce last admin" pattern
//    (with a delay) for tokens that need administered operation until they
//    don't? Currently the last-admin guard prevents the LAST admin from
//    renouncing. Issuers who want to evolve from admin-controlled to
//    admin-less mid-life have no clean path. Not blocking for v1; flagged
//    for future consideration.
//
// 4. Should `Stablecoin` remain a separate enum value, or fully collapse
//    into Default (current draft)? Current draft drops `STABLECOIN` from
//    the enum because Default and Stablecoin share the address prefix and
//    are operationally identical except for the immutable `currency`
//    field. Worth team confirmation.
//
// 5. Address-prefix bytes (`0xB200`, `0xB201`) require chain-config
//    coordination to reserve those address ranges. Need to confirm with
//    the chain team that these prefix bytes are actually available for
//    reservation.
//
// 6. Address derivation algorithm (the bytes that follow the prefix) is
//    not specified at the interface level. Implementations should use a
//    salt-domain-separated hash so that Default and Stablecoin
//    derivations are uniquely keyed (same prefix, same salt input, but
//    distinct derivation domain). Lock down before reference impl.
