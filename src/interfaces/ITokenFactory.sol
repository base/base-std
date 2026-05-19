// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title ITokenFactory
/// @notice Singleton factory precompile for creating B-20 tokens of any
///         variant. A single entry point `createToken` dispatches on a
///         `TokenVariant` discriminator; per-variant creation arguments
///         are ABI-encoded into `params` and prefixed with a `version`
///         byte so the encoding can evolve without breaking the factory's
///         immutable surface. Creation is permissionless; the caller picks
///         the initial admin.
///
/// @dev    **Factory address.** The factory lives at the fixed address
///         `0xB20...000F`.
///
///         **Token address schema (20 bytes).**
///         - `[0:10]`  — `bytes10(0xB20...000)` shared prefix identifying a
///                       factory-created B-20.
///         - `[10]`    — `bytes1(variant)` (matches `TokenVariant`).
///         - `[11]`    — `bytes1(decimals)` — encoded in the address so
///                       `decimals()` is recoverable statelessly from the
///                       token address alone, avoiding a storage read on
///                       hot integration paths (AMMs, lending markets,
///                       wallets). For variants that hardcode decimals
///                       (Stablecoin, Security: 6), this byte is fixed
///                       at `0x06`.
///         - `[12:20]` — `bytes8(keccak256(abi.encode(msg.sender, salt)))`.
///
///         **Variant evolution.** Adding new required fields to an
///         existing variant after launch is NOT supported: the factory is
///         an immutable precompile, and downstream protocols (e.g.
///         Clanker-style launchers) depend on the surface. Schemas evolve
///         in two ways:
///         1. Bumping the `version` byte at the head of a variant's
///            params struct and ABI-decoding accordingly. Old versions
///            remain valid forever.
///         2. Customizing per-token configuration via `initCalls` (see
///            below) instead of growing the params struct.
///
///         **`initCalls`.** After the token is deployed and the bootstrap
///         state is set, each entry in `initCalls` is invoked on the new
///         token with `msg.sender == factory` and the factory acting as
///         if it held `DEFAULT_ADMIN_ROLE`. This is how callers configure
///         optional post-creation state (initial mints, supply caps,
///         policy slot assignments, contract URI, initial pause state, etc.)
///         atomically in the same transaction as creation. The factory
///         does not interpret the call data; any revert in an init call
///         reverts the whole creation.
///
///         **Per-variant validation.** Variant-specific required-field
///         checks (e.g. stablecoins must specify a non-empty `currency`)
///         are applied at the end of the variant decode, after the
///         common version check, so each variant owns its own invariants.
interface ITokenFactory {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Variant of a B-20 token. Encoded in address byte `[10]`,
    ///         so `getTokenVariant` is a pure address-prefix read with no
    ///         storage lookup. `NONE` indicates the address is not a
    ///         B-20 token created by this factory.
    enum TokenVariant {
        NONE,
        DEFAULT,
        STABLECOIN,
        SECURITY
    }

    /// @notice Creation parameters for a Default-variant B-20 token.
    ///         ABI-encoded into the `params` argument of `createToken`.
    /// @param version       Encoding version. Currently `1`. Future
    ///                      hardforks may introduce additional versions
    ///                      with different field layouts; the leading
    ///                      byte selects the decoder.
    /// @param name          ERC-20 token name.
    /// @param symbol        ERC-20 token symbol.
    /// @param initialAdmin  Initial holder of `DEFAULT_ADMIN_ROLE`. All
    ///                      post-creation admin operations (including any
    ///                      ranout through `initCalls`) ultimately
    ///                      authorize against this account once the
    ///                      bootstrap init returns.
    /// @param decimals      ERC-20 decimals. MUST be in `[2, 18]`.
    ///                      Encoded into address byte `[11]` for
    ///                      stateless retrieval.
    struct B20CreateParams {
        uint8 version;
        string name;
        string symbol;
        address initialAdmin;
        uint8 decimals;
    }

    /// @notice Creation parameters for a Stablecoin-variant B-20 token.
    /// @param version       Encoding version. Currently `1`.
    /// @param name          ERC-20 token name.
    /// @param symbol        ERC-20 token symbol.
    /// @param initialAdmin  Initial holder of `DEFAULT_ADMIN_ROLE`.
    /// @param currency      Immutable currency identifier (e.g. "USD",
    ///                      "EUR", "XAU"). Required: empty string
    ///                      reverts. See `IB20Stablecoin.currency` for
    ///                      the convention.
    /// @dev    Decimals are fixed at `6` (the SPL stablecoin convention)
    ///         and encoded as `0x06` in address byte `[11]`. There is no
    ///         decimals field on this struct.
    struct B20StablecoinCreateParams {
        uint8 version;
        string name;
        string symbol;
        address initialAdmin;
        string currency;
    }

    /// @notice Creation parameters for a Security-variant B-20 token.
    /// @param version            Encoding version. Currently `1`.
    /// @param name               ERC-20 token name.
    /// @param symbol             ERC-20 token symbol.
    /// @param initialAdmin       Initial holder of `DEFAULT_ADMIN_ROLE`.
    /// @param isin               International Securities Identification
    ///                           Number. Required: empty string reverts.
    ///                           Additional identifiers (CUSIP, FIGI,
    ///                           SEDOL) can be attached post-creation
    ///                           via `IB20Security.updateSecurityIdentifier`.
    /// @param minimumRedeemable  Initial value of `minimumRedeemable`.
    ///                           Use `0` to allow any non-zero redemption.
    /// @dev    Decimals are fixed at `6` and encoded as `0x06` in address
    ///         byte `[11]`. Security tokens have no `initialSupply`
    ///         parameter: all issuance flows through `create`
    ///         (rate-limited compliant path) or `adminMint` (cold-path
    ///         batch with announcement coupling) after deployment.
    struct B20SecurityCreateParams {
        uint8 version;
        string name;
        string symbol;
        address initialAdmin;
        string isin;
        uint256 minimumRedeemable;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice A token already exists at the deterministic address
    ///         derived from `(variant, decimals, msg.sender, salt)`.
    ///         Caller must use a different salt.
    error TokenAlreadyExists(address token);

    /// @notice `variant` is not a recognized `TokenVariant` (or is
    ///         `NONE`, which is invalid for creation).
    error InvalidVariant();

    /// @notice The leading `version` byte in `params` does not match
    ///         any known encoding for the requested variant.
    error UnsupportedVersion(uint8 version);

    /// @notice The provided decimals value is outside the variant's
    ///         allowed range. Default tokens require `[2, 18]`;
    ///         Stablecoin and Security tokens hardcode `6` and do not
    ///         accept a caller-supplied value.
    error InvalidDecimals(uint8 decimals);

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /// @notice A required string argument was the empty string (e.g.
    ///         stablecoin `currency`, security `isin`).
    error MissingRequiredField();

    /// @notice One of the `initCalls` reverted. The factory bubbles the
    ///         underlying revert reason where the call returns one;
    ///         this error wraps empty reverts.
    error InitCallFailed(uint256 index);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once per `createToken` invocation. The common
    ///         fields cover the universal token-identity surface; all
    ///         variant-specific state changes (e.g. `currency`, `isin`,
    ///         supply cap, policy slots) are observable via the
    ///         token's own events as they're applied during the
    ///         bootstrap and `initCalls`.
    event TokenCreated(
        address indexed token,
        TokenVariant indexed variant,
        string name,
        string symbol,
        uint8 decimals
    );

    /*//////////////////////////////////////////////////////////////
                                 CREATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a B-20 token of the given `variant` at the
    ///         deterministic address derived from `(variant, decimals,
    ///         msg.sender, salt)`. `params` MUST be the ABI-encoded
    ///         variant-specific struct (`B20CreateParams`,
    ///         `B20StablecoinCreateParams`, or `B20SecurityCreateParams`),
    ///         leading with a `version` byte the factory uses to select
    ///         the decoder.
    ///
    ///         After the token is constructed and its identity state
    ///         (name, symbol, decimals, admin, variant-specific fields)
    ///         is sealed, the factory invokes each entry in `initCalls`
    ///         on the new token, acting as if it held the token's
    ///         `DEFAULT_ADMIN_ROLE`. This is the supported path for
    ///         configuring all optional post-creation state atomically:
    ///         initial mints, supply caps, policy slot assignments,
    ///         initial pause state, contract URI, etc. Any init-call revert
    ///         reverts the entire creation.
    ///
    ///         Emits `TokenCreated` once the token's identity is sealed
    ///         and before any `initCalls` are dispatched, so init-call
    ///         effects appear strictly after the creation event in the
    ///         log order.
    /// @param variant    Which variant struct `params` decodes as.
    /// @param salt       Caller-chosen salt for deterministic address
    ///                   derivation.
    /// @param params     ABI-encoded variant-specific creation struct,
    ///                   leading with the version byte.
    /// @param initCalls  Optional admin-context bootstrap calls invoked
    ///                   on the new token after identity is sealed.
    /// @return token     The address of the newly created token.
    function createToken(
        TokenVariant variant,
        bytes32 salt,
        bytes calldata params,
        bytes[] calldata initCalls
    ) external returns (address token);

    /*//////////////////////////////////////////////////////////////
                            ADDRESS QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deterministic address `createToken` would
    ///         assign for `(variant, decimals, sender, salt)`. Address
    ///         derivation depends only on these four inputs; the
    ///         remaining `params` fields do not affect the address.
    /// @dev    `variant` and `decimals` are both required because both
    ///         are encoded into the address (bytes `[10]` and `[11]`).
    ///         For Stablecoin and Security variants, pass `decimals = 6`.
    function getTokenAddress(TokenVariant variant, uint8 decimals, address sender, bytes32 salt)
        external
        view
        returns (address);

    /// @notice Whether `token` was created by this factory. Recovered
    ///         from the address prefix (bytes `[0:10]`); no storage read.
    function isB20(address token) external view returns (bool);

    /// @notice Returns the variant of `token`. Returns `NONE` if `token`
    ///         is not a factory-created B-20. Recovered from address
    ///         byte `[10]`; no storage read.
    function getTokenVariant(address token) external view returns (TokenVariant);
}
