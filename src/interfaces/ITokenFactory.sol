// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title ITokenFactory
/// @notice Singleton factory precompile for creating B-20 tokens. Exposes
///         three creation methods, one per variant the caller wants:
///         `createDefault`, `createStablecoin`, `createSecurity`. Each
///         returns the address of the newly created token, deployed at
///         a deterministic location derived from the caller's salt.
///
/// @dev    **Variant identification.** B-20 tokens have arbitrary-looking
///         addresses (no reserved prefix). The chain maintains an
///         internal registry of "addresses that are B-20 tokens",
///         populated by this factory at creation time. Dispatch logic
///         on every call: if the target address is in the registry,
///         route to the B-20 precompile; otherwise dispatch to normal
///         EVM. `variantOf(token)` reads from that registry. The
///         rationale for this design (rather than reserving an address
///         prefix like 0xB200 / 0xB201) is in `FACTORY_DESIGN_NOTES.md`:
///         short version is that Base has millions of pre-existing
///         contracts spread across the entire 160-bit address space,
///         and reserving any short prefix would either break existing
///         contracts or require extensive scanning + grandfathering.
///
///         **Variants and address space.** Default and Stablecoin share
///         the same address derivation (a Stablecoin is structurally a
///         Default token with `currency` set). For a given
///         `(creator, salt)` pair, exactly ONE of `createDefault` or
///         `createStablecoin` can succeed; the other reverts with
///         `TokenAlreadyExists`. Security tokens use a different
///         derivation domain so their addresses never collide with
///         Default / Stablecoin tokens for the same `(creator, salt)`.
///
///         **The `TokenVariant` enum** has only `NONE`, `DEFAULT`,
///         `SECURITY`. There is no `STABLECOIN` value because Stablecoin
///         is detected by the immutable `currency()` field returning a
///         non-empty string, not by a separate variant marker. Use
///         `isStablecoin(token)` to detect the stablecoin sub-case.
///
///         **Address determinism.** Each `predict*Address` view returns
///         the deterministic address that the matching `create*` call
///         would assign for a given `(creator, salt)`. Addresses depend
///         on the variant derivation domain, the creator, and the salt
///         only, so callers can compute the address off-chain or
///         pre-fund it before deployment. `predictDefaultAddress` and
///         `predictStablecoinAddress` return the SAME address for the
///         same `(creator, salt)` pair (shared derivation).
///
///         **Permissionless.** Anyone may create a token of any variant.
///         The factory has no admin and no per-call gating beyond the
///         standard creator-pays-gas flow.
///
///         **Each token is independent.** The factory creates the token
///         and bootstrap-mints initial supply (for Default and
///         Stablecoin) atomically, then the token is fully self-
///         governing. Issuers who need wrappers / controllers (Bridge's
///         TIP20Controller pattern, CCS's beacon proxy) deploy those
///         separately as normal EVM contracts.
interface ITokenFactory {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Variant of a B-20 token. `NONE` indicates the address
    ///         is not a B-20 token registered with this factory.
    /// @dev    Stablecoin is NOT a separate variant value: Stablecoin
    ///         and Default tokens share the `DEFAULT` enum value AND
    ///         the same address derivation, distinguished only by
    ///         whether `currency()` returns a non-empty string. Use
    ///         the `isStablecoin(token)` convenience view to identify
    ///         the stablecoin sub-case.
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
    ///                               definitions. The factory validates
    ///                               that only bits valid for this
    ///                               variant are set; reverts with
    ///                               `InvalidCapabilities` otherwise.
    ///                               For Default tokens, only `PAUSABLE`
    ///                               and `CAP_MUTABLE` are valid.
    /// @param transferPolicyId       Initial value of `transferPolicyId`.
    ///                               Required field; caller MUST pass a
    ///                               value. The recommended default for
    ///                               tokens without compliance needs is
    ///                               policy ID `1` (always-allow). Pass
    ///                               policy ID `0` (always-reject) to
    ///                               start in a soft-paused state until
    ///                               compliance is configured.
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
    ///                               mints currently bypass the policy
    ///                               check. See FACTORY_DESIGN_NOTES.md.
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
    ///         derivation as Default tokens; for a given
    ///         `(creator, salt)` pair, exactly ONE of `createDefault`
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
    ///         Security tokens use a different address derivation
    ///         domain from Default and Stablecoin tokens; addresses
    ///         created via `createSecurity` will never collide with
    ///         addresses created via `createDefault` or
    ///         `createStablecoin`, even for the same `(creator, salt)`
    ///         pair.
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
    ///         not valid for this variant. The factory validates that:
    ///         (a) only currently-defined bits are set (no reserved /
    ///         future bits), and (b) only variant-appropriate bits are
    ///         set (e.g. `SECURITY_*` bits only on Security tokens).
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
    ///         address derived from `(DEFAULT derivation, msg.sender, params.salt)`.
    ///         Registers the new address with the chain's B-20 token
    ///         registry. If `params.initialSupply > 0`, mints that
    ///         amount to `params.initialSupplyRecipient` atomically as
    ///         a bootstrap operation.
    /// @dev    The bootstrap mint BYPASSES the transfer policy check
    ///         (the policy referenced by `params.transferPolicyId` may
    ///         legitimately not authorize the recipient yet at creation
    ///         time). Subsequent mints go through the normal policy
    ///         hook. **Open design question** (see
    ///         FACTORY_DESIGN_NOTES.md): should the bootstrap mint
    ///         instead require the policy to authorize the recipient?
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
    ///         address derived from `(DEFAULT derivation, msg.sender, params.salt)`.
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
    ///         address derived from `(SECURITY derivation, msg.sender, params.salt)`.
    ///         No bootstrap mint; security tokens use `create`
    ///         (rate-limited compliant issuance) or `adminMint`
    ///         (cold-path batch with announcement coupling) for
    ///         issuance after deployment.
    /// @dev    Security tokens use a different address derivation
    ///         domain from Default and Stablecoin tokens; addresses
    ///         created via `createSecurity` will never collide with
    ///         addresses created via `createDefault` or
    ///         `createStablecoin`, even for the same `(creator, salt)`
    ///         pair.
    function createSecurity(CreateSecurityTokenParams calldata params) external returns (address token);

    /*//////////////////////////////////////////////////////////////
                          ADDRESS PREDICTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deterministic address that `createDefault`
    ///         would assign for the given `(creator, salt)`. Depends
    ///         only on the variant derivation domain, creator, and
    ///         salt; not on any of the other creation parameters.
    /// @dev    Returns the SAME address as `predictStablecoinAddress`
    ///         for the same `(creator, salt)` pair, because Default
    ///         and Stablecoin share the address derivation. Callers
    ///         who want both a Default and a Stablecoin token must
    ///         use different salts.
    function predictDefaultAddress(address creator, bytes32 salt) external view returns (address);

    /// @notice Returns the deterministic address that `createStablecoin`
    ///         would assign. Same as `predictDefaultAddress` for the
    ///         same `(creator, salt)` pair.
    function predictStablecoinAddress(address creator, bytes32 salt) external view returns (address);

    /// @notice Returns the deterministic address that `createSecurity`
    ///         would assign. Distinct from `predictDefaultAddress` /
    ///         `predictStablecoinAddress` because Security uses a
    ///         different derivation domain.
    function predictSecurityAddress(address creator, bytes32 salt) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                         VARIANT INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the variant of `token`. Returns `NONE` if
    ///         `token` is not in the chain's B-20 token registry
    ///         (i.e. was not created by this factory).
    /// @dev    Reads from the chain-level B-20 registry (one storage
    ///         slot read). Returns `DEFAULT` for any token created
    ///         via `createDefault` OR `createStablecoin` (they share
    ///         the variant marker). To distinguish the stablecoin
    ///         sub-case, use `isStablecoin(token)`.
    function variantOf(address token) external view returns (TokenVariant);

    /// @notice Convenience: `variantOf(token) != NONE`.
    function isB20(address token) external view returns (bool);

    /// @notice Convenience: returns true if `token` is a B-20 token
    ///         AND its `currency()` accessor returns a non-empty
    ///         string, indicating it was created via
    ///         `createStablecoin` rather than `createDefault`.
    ///         Returns false for non-B-20 addresses, for Security
    ///         tokens (no `currency` accessor), and for Default
    ///         tokens with empty `currency`.
    /// @dev    Reads from the token's storage (one external call) in
    ///         addition to the registry lookup.
    function isStablecoin(address token) external view returns (bool);
}
