// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IB20Factory
/// @notice Singleton factory precompile for creating B-20 tokens of any
///         variant. A single entry point `createToken` dispatches on a
///         `B20Variant` discriminator; per-variant creation arguments
///         are ABI-encoded into `params` and prefixed with a `version`
///         byte so the encoding can evolve without breaking the factory's
///         immutable surface. Creation is permissionless; the caller picks
///         the initial admin.
///
/// @dev    **Factory address.** The factory lives at the fixed address
///         `0xB20F00000000000000000000000000000000000F`. The `0xB20F`
///         prefix is deliberately distinct from the B-20 token prefix
///         `0xB200` (byte `[1]` differs), so `isB20(factory)` returns
///         false unambiguously.
///
///         **Token address schema (20 bytes).**
///         - `[0:10]`  — `bytes10(0xB200000000000000000000)` shared
///                       prefix identifying a factory-created B-20.
///         - `[10]`    — `bytes1(variant)` (matches `B20Variant`).
///         - `[11:20]` — `bytes9(keccak256(abi.encode(msg.sender, salt)))`.
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
///         token with `msg.sender == factory`. These calls are entirely
///         privileged: every authorization gate the token would normally
///         enforce against the caller (role checks, transfer-policy
///         checks, capability gates) is bypassed for calls originating
///         from the factory during the bootstrap window. The window
///         closes the moment `createToken` returns; from that point
///         forward every call is subject to the standard role and policy
///         checks. The factory is NOT added to any role on the token;
///         "privileged" means authorization is skipped for the bootstrap
///         caller, not that the factory has been granted authority that
///         persists. Invariants intrinsic to token correctness
///         (supply-cap math, balance accounting, etc.) are still enforced.
///
///         This is the supported path for configuring optional
///         post-creation state (initial mints, supply caps, policy slot
///         assignments, contract URI, initial pause state, etc.)
///         atomically in the same transaction as creation. The factory
///         does not interpret the call data; any revert in an init call
///         reverts the whole creation.
///
///         **Per-variant validation.** Variant-specific required-field
///         checks (e.g. stablecoins must specify a non-empty `currency`)
///         are applied at the end of the variant decode, after the
///         common version check, so each variant owns its own invariants.
interface IB20Factory {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Variant of a B-20 token. Encoded in address byte `[10]`,
    ///         so the variant of a B-20 address is a pure address-prefix
    ///         read with no storage lookup. Whether an address is a
    ///         factory-created B-20 in the first place is answered by
    ///         `isB20` (a prefix check on bytes `[0:10]`); the variant
    ///         byte itself does not need an "absent" sentinel.
    enum B20Variant {
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
    ///                      post-creation admin operations authorize
    ///                      against this account (and any additional
    ///                      admins it later grants). The bootstrap
    ///                      `initCalls` are NOT subject to this check:
    ///                      they execute with full privilege regardless
    ///                      of role state, and the privileged window
    ///                      closes the moment `createToken` returns.
    ///                      May be `address(0)` for the "demonstrate no
    ///                      owner" case (memecoins, credibly-neutral
    ///                      tokens). When zero, no role is granted at
    ///                      creation and the token has no admin: no
    ///                      role grants, policy changes, or pauses are
    ///                      ever possible post-creation. The
    ///                      `renounceLastAdmin` path is the alternative
    ///                      for tokens that need an admin during setup
    ///                      and then want to evolve to admin-less.
    struct B20CreateParams {
        uint8 version;
        string name;
        string symbol;
        address initialAdmin;
    }

    /// @notice Creation parameters for a Stablecoin-variant B-20 token.
    /// @param version       Encoding version. Currently `1`.
    /// @param name          ERC-20 token name.
    /// @param symbol        ERC-20 token symbol.
    /// @param initialAdmin  Initial holder of `DEFAULT_ADMIN_ROLE`.
    /// @param currency      Immutable ISO-4217-shaped fiat identifier
    ///                      this stablecoin tracks (e.g. `"USD"`,
    ///                      `"EUR"`). Validated as exactly three
    ///                      uppercase ASCII letters (`A`–`Z`);
    ///                      membership against the ISO 4217 register is
    ///                      NOT enforced on-chain. Anything failing the
    ///                      format check reverts with
    ///                      `InvalidCurrency(code)`. The field is
    ///                      self-declared — consumers using
    ///                      `currency()` for authorization or routing
    ///                      MUST layer their own issuer / contract
    ///                      allowlist on top. See
    ///                      `docs/b20/stablecoin/currency-validation.md`.
    /// @dev    Decimals are fixed at `6`. There is no decimals field
    ///         and no setter for `currency` — both are fixed for the
    ///         token's lifetime at creation.
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
    /// @dev    Decimals are fixed at `6`. Security tokens have no `initialSupply`
    ///         parameter: all issuance flows through `create`
    ///         (rate-limited compliant path) or `adminMint` (cold-path
    ///         batch with announcement coupling) after deployment.
    ///
    ///         For the Security variant, the `REDEEM_SENDER_POLICY`
    ///         slot defaults to the always-block built-in (policy ID
    ///         `1`) rather than always-allow, so redemption is closed by
    ///         default and an admin must opt-in by pointing the slot at
    ///         an allowlist (or another policy) before any holder can
    ///         call `redeem`. To open redemption at creation, override
    ///         the slot atomically by including an
    ///         `updatePolicy(REDEEM_SENDER_POLICY, <policyId>)` entry
    ///         in `initCalls`.
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
    ///         derived from `(variant, msg.sender, salt)`.
    ///         Caller must use a different salt.
    error TokenAlreadyExists(address token);

    /// @notice `variant` is not a recognized `B20Variant`. Reached
    ///         only when the factory is invoked with a raw variant byte
    ///         outside the enum range (typed `createToken` callers are
    ///         rejected by ABI decoding before this check fires).
    error InvalidVariant();

    /// @notice The leading `version` byte in `params` does not match
    ///         any known encoding for the requested variant.
    error UnsupportedVersion(uint8 version, B20Variant variant);

    /// @notice A required string argument was the empty string (e.g.
    ///         security `isin`). The stablecoin `currency` field has
    ///         its own format check and reverts with `InvalidCurrency`
    ///         instead — including for the empty string — so callers
    ///         get a single, diagnostic-carrying error for every
    ///         currency rejection rather than two disjoint failure
    ///         modes for the same field.
    error MissingRequiredField();

    /// @notice The stablecoin `currency` field was not exactly three
    ///         uppercase ASCII letters (`A`–`Z`). Carries the offending
    ///         string verbatim for diagnostics.
    /// @dev    See `docs/b20/stablecoin/currency-validation.md`.
    error InvalidCurrency(string code);

    /// @notice One of the `initCalls` reverted. The factory bubbles the
    ///         underlying revert reason where the call returns one;
    ///         this error wraps empty reverts.
    error InitCallFailed(uint256 index);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once per `createToken` invocation. The fields
    ///         cover the universal token-identity surface only;
    ///         variant-specific state changes (e.g. `currency`, `isin`,
    ///         supply cap, policy slots) are observable via the
    ///         token's own events as they're applied during `initCalls`.
    /// @dev    The initial admin grant (when `initialAdmin != address(0)`)
    ///         is announced via the standard `RoleGranted(DEFAULT_ADMIN_ROLE,
    ///         admin, factory)` event emitted from the token's own
    ///         context during the same transaction — NOT as a field on
    ///         this event. Role state is always observable via the
    ///         `RoleGranted` / `RoleRevoked` event stream from the token;
    ///         `B20Created` is the token-identity signal only. The
    ///         "demonstrate no owner" path (`initialAdmin == address(0)`)
    ///         skips the grant and emits no `RoleGranted` at bootstrap.
    event B20Created(address indexed token, B20Variant indexed variant, string name, string symbol, uint8 decimals);

    /*//////////////////////////////////////////////////////////////
                                 CREATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a B-20 token of the given `variant` at the
    ///         deterministic address derived from `(variant, msg.sender, salt)`.
    ///         `params` MUST be the ABI-encoded
    ///         variant-specific struct (`B20CreateParams`,
    ///         `B20StablecoinCreateParams`, or `B20SecurityCreateParams`),
    ///         leading with a `version` byte the factory uses to select
    ///         the decoder.
    ///
    ///         After the token is constructed and its identity state
    ///         (name, symbol, decimals, admin, variant-specific fields)
    ///         is sealed, the factory invokes each entry in `initCalls`
    ///         on the new token. These calls are entirely privileged:
    ///         all authorization gates the token would normally enforce
    ///         against the caller (role checks, transfer-policy checks,
    ///         capability gates) are bypassed for calls from the factory
    ///         during this bootstrap window. The factory is not added to
    ///         any role; the bypass is bound to the call site, not to
    ///         RBAC state. Once `createToken` returns, every subsequent
    ///         call on the token is subject to the standard checks.
    ///
    ///         This is the supported path for configuring all optional
    ///         post-creation state atomically: initial mints, supply
    ///         caps, policy slot assignments, initial pause state,
    ///         contract URI, etc. Any init-call revert reverts the
    ///         entire creation.
    ///
    ///         Emits `B20Created` once the token's identity is sealed
    ///         and before any `initCalls` are dispatched, so init-call
    ///         effects appear strictly after the creation event in the
    ///         log order.
    /// @param variant    Which variant struct `params` decodes as.
    /// @param salt       Caller-chosen salt for deterministic address
    ///                   derivation.
    /// @param params     ABI-encoded variant-specific creation struct,
    ///                   leading with the version byte.
    /// @param initCalls  Optional bootstrap calls invoked on the new
    ///                   token after identity is sealed. Executed as
    ///                   fully privileged calls from the factory: all
    ///                   token-side authorization checks are bypassed
    ///                   for this window only.
    /// @return token     The address of the newly created token.
    function createB20(B20Variant variant, bytes32 salt, bytes calldata params, bytes[] calldata initCalls)
        external
        returns (address token);

    /*//////////////////////////////////////////////////////////////
                            ADDRESS QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the deterministic address `createToken` would
    ///         assign for `(variant, sender, salt)`. Address derivation
    ///         depends only on these inputs; the remaining `params`
    ///         fields (including decimals, which are fixed by variant)
    ///         do not affect the address.
    function getB20Address(B20Variant variant, address sender, bytes32 salt) external view returns (address);

    /// @notice Whether `token` was created by this factory. Recovered
    ///         from the address prefix (bytes `[0:10]`); no storage read.
    function isB20(address token) external view returns (bool);

    /// @notice Whether the token at `token` has been initialized by this
    ///         factory (i.e. `createToken` ran to completion at that
    ///         address). Returns `false` for B-20-prefixed addresses
    ///         whose deterministic slot has not yet been claimed by a
    ///         `createToken` call, and for any address that is not a
    ///         B-20 at all. The bootstrap window (the `initCalls` loop
    ///         inside `createToken`) is fully privileged but not yet
    ///         initialized; this flag flips exactly once, at the moment
    ///         `createToken` returns.
    function isB20Initialized(address token) external view returns (bool);
}
