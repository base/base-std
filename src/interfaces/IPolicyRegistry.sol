// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IPolicyRegistry
/// @notice Singleton registry of transfer-authorization policies for B-20
///         tokens. Each B-20 token holds a single `transferPolicyId`
///         pointing into this registry; on every transfer, mint, or
///         redeem, the token consults the registry via the
///         `authorize{Transfer,Mint,Redeem}` functions to determine
///         whether the operation is permitted.
///
/// @dev    **Design philosophy: enshrine everything, evolve via hardfork.**
///         All policy logic and state lives in this precompile. There
///         are no callback policies that delegate to user-provided EVM
///         contracts; that path was explicitly ruled out because it
///         defeats the sequencer optimizations that motivate the
///         enshrined-token model in the first place. Adding new policy
///         capabilities (new check primitives, richer composition) is
///         done via hardfork: the policy type enum is reserved-extensible,
///         and new types ship with their own creation, administration,
///         and authorization branches.
///
///         **Authorization contract.** The hot-path authorize functions
///         take the FULL operation context (`from`, `to`, `amount`) and
///         REVERT on denial with a typed error indicating the reason
///         (e.g. `RateLimitExceeded`, `KYCNotVerified`, `TimeLockNotElapsed`).
///         They MAY mutate state (rate-limit consumption, etc.). On
///         success they return `true` as an explicit success signal.
///         Tokens calling these functions need not check the bool;
///         they should let the revert bubble up. The bool exists so
///         that integration patterns that DO want to check (e.g.
///         routers that try multiple policy paths) can use try/catch.
///
///         **Off-chain simulation.** Every authorize function has a
///         matching `previewAuthorize*` view counterpart that does
///         NOT mutate state and returns `bool` (no revert). Wallets
///         and indexers use the preview functions to predict whether
///         a transfer will succeed without paying gas.
///
///         **Built-in policy IDs.** ID `0` is the always-reject policy;
///         ID `1` is the always-allow policy. Custom policy IDs start
///         at `2` and are assigned monotonically by `policyIdCounter`.
///
///         **Cycles are structurally impossible.** Combinator policies
///         (COMPOUND, AND, OR) reference other policies by ID. Since
///         a referenced policy must already exist when its parent is
///         created, parent policy IDs are always strictly greater than
///         their children. The policy graph is a DAG by construction,
///         no cycle detection needed at evaluation time.
///
///         **Recursion depth bound.** AND/OR composition is recursive
///         (AND can contain ANDs etc.). To keep authorize calls
///         predictable for the sequencer, evaluation depth is bounded
///         at `MAX_COMPOSITION_DEPTH` (currently 8). Creating a policy
///         that would exceed this depth at evaluation time reverts with
///         `CompositionDepthExceeded`.
///
///         **Versioning by hardfork.** Sections of this interface marked
///         "v1" ship in the initial hardfork. Sections marked "future"
///         are designed forward-compatibly: their function signatures
///         are part of the canonical ABI even though the underlying
///         policy types are not yet implemented. A future hardfork
///         enables the policy types behind these signatures without
///         changing the calling convention. The forward-compat
///         declarations exist so that token-side authorize calls don't
///         need to grow their ABI when new policy primitives ship.
interface IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum nesting depth for AND/OR combinator evaluation.
    ///         A policy graph that would require more than this many
    ///         levels of recursion to evaluate is rejected at creation.
    function MAX_COMPOSITION_DEPTH() external view returns (uint8);

    /// @notice Maximum number of constituent policy IDs in a single
    ///         AND or OR combinator policy. Bounds the per-call gas
    ///         cost and storage layout.
    function MAX_COMBINATOR_CONSTITUENTS() external view returns (uint8);

    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy type discriminator. Append-only across protocol
    ///         versions: existing values keep their meanings forever,
    ///         new types are added in higher positions in future
    ///         hardforks.
    enum PolicyType {
        // ===== v1 =====
        WHITELIST, // 0: address-set membership; allow if in set
        BLACKLIST, // 1: address-set membership; allow if NOT in set
        COMPOUND, // 2: per-role slots (sender/recipient/mintRecip/redeemer)
        AND, // 3: all constituent policies must authorize
        OR, // 4: any constituent policy must authorize
        // ===== future hardfork: stateful single-context primitives =====
        RATE_LIMIT, // 5: per-address rolling capacity
        TIME_LOCK, // 6: per-address (or global) unlock timestamp
        AMOUNT_CAP // 7: per-tx amount limit (with optional per-address overrides)
    }

    /// @notice Top-level data for any policy.
    /// @param policyType The discriminator above.
    /// @param admin      The address authorized to mutate this policy's
    ///                   configuration. Zero for COMPOUND, AND, OR
    ///                   (structurally immutable: their constituent IDs
    ///                   cannot be changed, and they have no per-policy
    ///                   state to mutate).
    struct PolicyData {
        PolicyType policyType;
        address admin;
    }

    /// @notice Constituent policy IDs for a COMPOUND policy. Each slot
    ///         maps to one transfer role; the policy referenced by that
    ///         slot is evaluated against the address fulfilling that
    ///         role. Slots can reference any single-context policy
    ///         (WHITELIST, BLACKLIST, AND, OR, RATE_LIMIT, TIME_LOCK,
    ///         AMOUNT_CAP); slots cannot reference other COMPOUND
    ///         policies. Use built-in ID `1` (always-allow) for any
    ///         slot that has no constraint.
    struct CompoundPolicyData {
        uint64 senderPolicyId; // checked on transfer's `from`
        uint64 recipientPolicyId; // checked on transfer's `to`
        uint64 mintRecipientPolicyId; // checked on mint's `to`
        uint64 redeemerPolicyId; // checked on redeem's `holder` (caller)
    }

    /// @notice Constituent policy IDs for an AND or OR combinator. Each
    ///         constituent must be a single-context policy (i.e. NOT a
    ///         COMPOUND); combinators of combinators ARE allowed and
    ///         enable arbitrary boolean expression trees over the
    ///         primitive checks. Constituent count is bounded by
    ///         `MAX_COMBINATOR_CONSTITUENTS`; recursion depth across
    ///         nested combinators is bounded by `MAX_COMPOSITION_DEPTH`.
    struct CombinatorPolicyData {
        uint64[] constituentPolicyIds;
    }

    // ============= future hardfork: stateful primitive structs =============

    /// @notice Configuration for a RATE_LIMIT policy. State per-address
    ///         lives in a separate mapping (`rateLimitState`). On each
    ///         authorize call against a RATE_LIMIT policy, the state
    ///         is replenished linearly based on elapsed time and
    ///         debited by the call's `amount`. Authorize reverts with
    ///         `RateLimitExceeded` if remaining capacity is below
    ///         `amount`.
    /// @dev    `maxAmount` packed to fit alongside `interval` and the
    ///         per-address state in a single storage slot.
    struct RateLimitConfig {
        uint96 maxAmount;
        uint40 interval; // seconds for full replenishment
    }

    /// @notice Per-address state for a RATE_LIMIT policy.
    struct RateLimitState {
        uint96 remaining;
        uint40 lastConsumeTimestamp;
    }

    /// @notice Configuration for a TIME_LOCK policy. If `perAddress` is
    ///         true, the unlock timestamp is read from
    ///         `timeLockUnlock(policyId, user)` (per-address); if
    ///         false, the policy has a single `globalUnlockTimestamp`
    ///         that applies to every caller. Authorize reverts with
    ///         `TimeLockNotElapsed` until the relevant timestamp has
    ///         passed.
    struct TimeLockConfig {
        bool perAddress;
        uint64 globalUnlockTimestamp;
    }

    /// @notice Configuration for an AMOUNT_CAP policy. `maxPerTx` is
    ///         the default cap; per-address overrides may be set via
    ///         `setAmountCapOverride`. Authorize reverts with
    ///         `AmountCapExceeded` if the call's `amount` exceeds the
    ///         applicable cap.
    struct AmountCapConfig {
        uint256 maxPerTx;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    // ===== Generic =====

    /// @notice Caller is not the admin of the referenced policy.
    error Unauthorized();

    /// @notice The referenced policy ID does not exist.
    error PolicyNotFound(uint64 policyId);

    /// @notice The operation is incompatible with the policy's type
    ///         (e.g. calling `modifyPolicyWhitelist` on a BLACKLIST
    ///         policy, or referencing a COMPOUND from an AND constituent).
    error IncompatiblePolicyType(uint64 policyId, PolicyType actualType);

    /// @notice An address argument was the zero address.
    error ZeroAddress();

    /// @notice An invalid policy type was passed (e.g. COMPOUND to the
    ///         simple-policy creator).
    error InvalidPolicyType(PolicyType policyType);

    // ===== Composition =====

    /// @notice An AND/OR combinator was created with more than
    ///         `MAX_COMBINATOR_CONSTITUENTS` entries, or with zero
    ///         entries.
    error InvalidCombinatorSize(uint256 size, uint256 max);

    /// @notice Creating this policy would result in a composition tree
    ///         exceeding `MAX_COMPOSITION_DEPTH` levels at evaluation
    ///         time. Flatten the tree or split into multiple top-level
    ///         policies.
    error CompositionDepthExceeded(uint8 depth, uint8 max);

    /// @notice An AND/OR combinator constituent was a COMPOUND policy.
    ///         Combinators only accept single-context policies.
    error CombinatorRejectsCompound(uint64 policyId);

    // ===== Authorization denials =====

    /// @notice The active policy denied the operation. Generic catchall
    ///         used by WHITELIST and BLACKLIST denials.
    error PolicyDenied(uint64 policyId, address user);

    /// @notice OR combinator: every constituent denied. Indicates which
    ///         OR was the outermost failure for debugging.
    error AllConstituentsDenied(uint64 orPolicyId);

    /// @notice RATE_LIMIT denial. Reports the remaining capacity at the
    ///         time of the call so the caller knows how much they could
    ///         have spent.
    error RateLimitExceeded(uint64 policyId, address user, uint256 remaining, uint256 requested);

    /// @notice TIME_LOCK denial. Reports the unlock timestamp so the
    ///         caller knows when the operation will succeed.
    error TimeLockNotElapsed(uint64 policyId, address user, uint64 unlockAt);

    /// @notice AMOUNT_CAP denial. Reports the cap that was exceeded.
    error AmountCapExceeded(uint64 policyId, uint256 cap, uint256 requested);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // ===== Policy lifecycle =====

    /// @notice Emitted when a new simple policy (WHITELIST or BLACKLIST)
    ///         is created. Compound, AND, OR, and stateful policies
    ///         emit their own typed creation events.
    event PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType);

    /// @notice Emitted when a new COMPOUND policy is created. Carries
    ///         all four slot policy IDs for indexer convenience.
    event CompoundPolicyCreated(
        uint64 indexed policyId,
        address indexed creator,
        uint64 senderPolicyId,
        uint64 recipientPolicyId,
        uint64 mintRecipientPolicyId,
        uint64 redeemerPolicyId
    );

    /// @notice Emitted when a new AND combinator policy is created.
    event AndPolicyCreated(uint64 indexed policyId, address indexed creator, uint64[] constituentPolicyIds);

    /// @notice Emitted when a new OR combinator policy is created.
    event OrPolicyCreated(uint64 indexed policyId, address indexed creator, uint64[] constituentPolicyIds);

    /// @notice Emitted when a new RATE_LIMIT policy is created.
    event RateLimitPolicyCreated(
        uint64 indexed policyId, address indexed creator, address admin, uint96 maxAmount, uint40 interval
    );

    /// @notice Emitted when a new TIME_LOCK policy is created.
    event TimeLockPolicyCreated(
        uint64 indexed policyId, address indexed creator, address admin, bool perAddress, uint64 globalUnlockTimestamp
    );

    /// @notice Emitted when a new AMOUNT_CAP policy is created.
    event AmountCapPolicyCreated(uint64 indexed policyId, address indexed creator, address admin, uint256 maxPerTx);

    // ===== Policy administration =====

    /// @notice Emitted when a policy's admin is updated.
    event PolicyAdminUpdated(uint64 indexed policyId, address indexed updater, address indexed admin);

    /// @notice Emitted when a WHITELIST policy's membership is updated.
    event WhitelistUpdated(uint64 indexed policyId, address indexed updater, address indexed account, bool allowed);

    /// @notice Emitted when a BLACKLIST policy's membership is updated.
    event BlacklistUpdated(uint64 indexed policyId, address indexed updater, address indexed account, bool restricted);

    /// @notice Emitted when a RATE_LIMIT policy's configuration is updated.
    event RateLimitConfigUpdated(
        uint64 indexed policyId,
        address indexed updater,
        uint96 oldMaxAmount,
        uint40 oldInterval,
        uint96 newMaxAmount,
        uint40 newInterval
    );

    /// @notice Emitted when a TIME_LOCK policy's per-address unlock is
    ///         updated.
    event TimeLockUnlockUpdated(
        uint64 indexed policyId, address indexed updater, address indexed user, uint64 oldUnlockAt, uint64 newUnlockAt
    );

    /// @notice Emitted when an AMOUNT_CAP policy's default cap is updated.
    event AmountCapUpdated(
        uint64 indexed policyId, address indexed updater, uint256 oldMaxPerTx, uint256 newMaxPerTx
    );

    /// @notice Emitted when an AMOUNT_CAP policy's per-address override
    ///         is set or cleared.
    event AmountCapOverrideSet(
        uint64 indexed policyId, address indexed updater, address indexed user, uint256 maxPerTx
    );

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION (V1)
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes a transfer of `amount` from `from` to `to`
    ///         under `policyId`. Reverts on denial with a typed error
    ///         indicating the reason. Returns `true` on success as an
    ///         explicit success signal.
    /// @dev    For COMPOUND `policyId`, evaluates `senderPolicyId` for
    ///         `from` and `recipientPolicyId` for `to` (both with
    ///         `amount` context). For non-COMPOUND `policyId`,
    ///         evaluates the single policy for both `from` and `to` in
    ///         turn.
    ///
    ///         MAY mutate state (rate-limit consumption,
    ///         per-address stateful checks). Mutations are atomic with
    ///         the call: if the call reverts, all mutations are
    ///         reverted by EVM tx semantics.
    function authorizeTransfer(uint64 policyId, address from, address to, uint256 amount) external returns (bool);

    /// @notice Authorizes a mint of `amount` to `to` under `policyId`,
    ///         called by `minter`. Reverts on denial. Returns `true`
    ///         on success.
    /// @dev    For COMPOUND `policyId`, evaluates `mintRecipientPolicyId`
    ///         for `to` (with `amount` context). For non-COMPOUND
    ///         `policyId`, evaluates the single policy for `to`. Note
    ///         that `minter` is currently NOT consulted by any built-in
    ///         policy type; future stateful types (e.g. per-minter
    ///         rate limiting via RATE_LIMIT) would consume state keyed
    ///         on `minter`.
    function authorizeMint(uint64 policyId, address minter, address to, uint256 amount) external returns (bool);

    /// @notice Authorizes a redeem of `amount` by `holder` under
    ///         `policyId`. Reverts on denial. Returns `true` on success.
    /// @dev    For COMPOUND `policyId`, evaluates `redeemerPolicyId` for
    ///         `holder` (with `amount` context). For non-COMPOUND
    ///         `policyId`, evaluates the single policy for `holder`.
    ///         Tokens that don't offer redemption configure their
    ///         compound's `redeemerPolicyId` to the always-reject
    ///         built-in (ID `0`).
    function authorizeRedeem(uint64 policyId, address holder, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                            PREVIEW (V1)
    //////////////////////////////////////////////////////////////*/

    /// @notice Read-only preview of `authorizeTransfer`. Returns
    ///         `true` if the call would succeed; returns `false`
    ///         instead of reverting on denial. Does NOT mutate state.
    /// @dev    Useful for off-chain simulation and for on-chain routers
    ///         that want to try multiple policy paths.
    function previewAuthorizeTransfer(uint64 policyId, address from, address to, uint256 amount)
        external
        view
        returns (bool);

    /// @notice Read-only preview of `authorizeMint`.
    function previewAuthorizeMint(uint64 policyId, address minter, address to, uint256 amount)
        external
        view
        returns (bool);

    /// @notice Read-only preview of `authorizeRedeem`.
    function previewAuthorizeRedeem(uint64 policyId, address holder, uint256 amount) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          POLICY CREATION (V1)
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new simple policy (WHITELIST or BLACKLIST).
    ///         Permissionless; the caller picks the admin (typically
    ///         themselves or a multi-sig).
    /// @dev    Reverts with `InvalidPolicyType` if `policyType` is not
    ///         WHITELIST or BLACKLIST. Use `createCompoundPolicy`,
    ///         `createAndPolicy`, `createOrPolicy`, or one of the
    ///         stateful-policy creators for those types.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Same as `createPolicy`, but additionally seeds the
    ///         policy's member set with `accounts`.
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId);

    /// @notice Creates a new COMPOUND policy with four constituent
    ///         single-context policy IDs, one per transfer role.
    ///         Structurally immutable; cannot be modified after
    ///         creation. Use built-in ID `1` (always-allow) for any
    ///         slot that has no constraint, or `0` (always-reject) for
    ///         a slot that should hard-block the corresponding role
    ///         (e.g. `redeemerPolicyId = 0` on a token without
    ///         redemption).
    /// @dev    Each constituent must exist and must be a single-context
    ///         policy (any policy type EXCEPT COMPOUND). Reverts with
    ///         `CombinatorRejectsCompound` if a slot references a
    ///         COMPOUND, or `PolicyNotFound` if any ID is unknown.
    function createCompoundPolicy(
        uint64 senderPolicyId,
        uint64 recipientPolicyId,
        uint64 mintRecipientPolicyId,
        uint64 redeemerPolicyId
    ) external returns (uint64 newPolicyId);

    /// @notice Creates a new AND combinator policy. Authorizes only if
    ///         ALL constituent policies authorize.
    /// @dev    Permissionless. Each constituent must exist and must NOT
    ///         be a COMPOUND policy. Reverts with `InvalidCombinatorSize`
    ///         if `constituentPolicyIds.length` is 0 or exceeds
    ///         `MAX_COMBINATOR_CONSTITUENTS`. Reverts with
    ///         `CompositionDepthExceeded` if the resulting evaluation
    ///         tree would exceed `MAX_COMPOSITION_DEPTH`.
    ///
    ///         Constituents may themselves be AND or OR policies,
    ///         enabling arbitrary boolean expression trees over the
    ///         primitive checks. Cycles are structurally impossible
    ///         because each constituent must already exist (have a
    ///         lower ID) when the combinator is created.
    function createAndPolicy(uint64[] calldata constituentPolicyIds) external returns (uint64 newPolicyId);

    /// @notice Creates a new OR combinator policy. Authorizes if ANY
    ///         constituent authorizes; reverts with
    ///         `AllConstituentsDenied` if all deny.
    /// @dev    Same constraints as `createAndPolicy`.
    ///
    ///         OR composition with stateful constituents has subtle
    ///         semantics: constituents are evaluated in order, and the
    ///         first one to authorize commits any state mutations it
    ///         performed (e.g. consuming rate-limit capacity). Earlier
    ///         constituents that ran but denied do NOT commit state.
    ///         Implementations evaluate stateful constituents
    ///         non-mutatingly until one authorizes, then re-run that
    ///         constituent in mutating mode to commit. (Equivalently:
    ///         use the preview-then-commit pattern internally.)
    function createOrPolicy(uint64[] calldata constituentPolicyIds) external returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                  POLICY CREATION (FUTURE HARDFORK)
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new RATE_LIMIT policy. Each address gets its
    ///         own rolling capacity that replenishes linearly over
    ///         `interval` seconds, up to `maxAmount`. The first
    ///         authorize call against a fresh address starts with
    ///         `maxAmount` capacity.
    /// @dev    **Future hardfork.** The function signature is part of
    ///         the canonical ABI to allow forward-compatible token
    ///         calls; the implementation reverts with `InvalidPolicyType`
    ///         until the relevant hardfork enables RATE_LIMIT.
    ///
    ///         Use cases: per-minter quotas (replaces the per-token
    ///         CCS pattern with a shared registry-level construct),
    ///         per-account spending caps with daily / weekly windows.
    function createRateLimitPolicy(address admin, uint96 maxAmount, uint40 interval)
        external
        returns (uint64 newPolicyId);

    /// @notice Creates a new TIME_LOCK policy. If `perAddress` is true,
    ///         per-address unlock timestamps are set via
    ///         `setTimeLockUnlock`. If false, the single
    ///         `globalUnlockTimestamp` applies to every caller.
    /// @dev    **Future hardfork.** See `createRateLimitPolicy` note on
    ///         forward-compat.
    ///
    ///         Use cases: cliff vesting, regulatory holding-period
    ///         requirements, post-launch lockups for early holders.
    function createTimeLockPolicy(address admin, bool perAddress, uint64 globalUnlockTimestamp)
        external
        returns (uint64 newPolicyId);

    /// @notice Creates a new AMOUNT_CAP policy. `maxPerTx` is the
    ///         default cap; per-address overrides may be set via
    ///         `setAmountCapOverride`.
    /// @dev    **Future hardfork.** See `createRateLimitPolicy` note on
    ///         forward-compat.
    ///
    ///         Use cases: anti-whale per-tx caps for fair launch
    ///         tokens, per-tx limits for stablecoin sanctions
    ///         compliance.
    function createAmountCapPolicy(address admin, uint256 maxPerTx) external returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                       POLICY ADMINISTRATION (V1)
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers admin rights for a non-combinator policy.
    ///         Caller must be the current admin. Reverts on COMPOUND,
    ///         AND, OR (which have no admin and are structurally
    ///         immutable).
    function setPolicyAdmin(uint64 policyId, address newAdmin) external;

    /// @notice Adds or removes an account from a WHITELIST policy.
    ///         Caller must be the policy admin. Reverts with
    ///         `IncompatiblePolicyType` if the policy is not WHITELIST.
    function modifyPolicyWhitelist(uint64 policyId, address account, bool allowed) external;

    /// @notice Adds or removes an account from a BLACKLIST policy.
    ///         Caller must be the policy admin. Reverts with
    ///         `IncompatiblePolicyType` if the policy is not BLACKLIST.
    function modifyPolicyBlacklist(uint64 policyId, address account, bool restricted) external;

    /*//////////////////////////////////////////////////////////////
              POLICY ADMINISTRATION (FUTURE HARDFORK)
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the (`maxAmount`, `interval`) configuration of
    ///         a RATE_LIMIT policy. Caller must be the policy admin.
    ///         Existing per-address state is NOT reset; the new
    ///         capacity simply applies to future replenishment.
    /// @dev    **Future hardfork.**
    function setRateLimitConfig(uint64 policyId, uint96 newMaxAmount, uint40 newInterval) external;

    /// @notice Resets the per-address rate-limit state for `user`,
    ///         giving them full capacity. Caller must be the policy
    ///         admin. Useful for one-off whitelist boosts or
    ///         compliance grants.
    /// @dev    **Future hardfork.**
    function resetRateLimitState(uint64 policyId, address user) external;

    /// @notice Sets the per-address unlock timestamp for `user` on a
    ///         per-address TIME_LOCK policy. Caller must be the policy
    ///         admin. Reverts if the policy is configured as
    ///         non-per-address (use `setTimeLockGlobalUnlock` instead).
    /// @dev    **Future hardfork.**
    function setTimeLockUnlock(uint64 policyId, address user, uint64 unlockAt) external;

    /// @notice Updates the global unlock timestamp on a non-per-address
    ///         TIME_LOCK policy. Caller must be the policy admin.
    /// @dev    **Future hardfork.**
    function setTimeLockGlobalUnlock(uint64 policyId, uint64 newUnlockAt) external;

    /// @notice Updates the default `maxPerTx` of an AMOUNT_CAP policy.
    ///         Caller must be the policy admin.
    /// @dev    **Future hardfork.**
    function setAmountCap(uint64 policyId, uint256 newMaxPerTx) external;

    /// @notice Sets a per-address `maxPerTx` override on an AMOUNT_CAP
    ///         policy. Pass `0` to clear the override (the user falls
    ///         back to the default cap). Caller must be the policy
    ///         admin.
    /// @dev    **Future hardfork.**
    function setAmountCapOverride(uint64 policyId, address user, uint256 maxPerTx) external;

    /*//////////////////////////////////////////////////////////////
                            POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The next policy ID that will be assigned. Starts at 2;
    ///         IDs 0 and 1 are reserved for the built-in always-reject
    ///         and always-allow policies respectively.
    function policyIdCounter() external view returns (uint64);

    /// @notice Whether `policyId` exists. Built-in IDs (0, 1) always
    ///         exist; custom IDs (>=2) exist iff they have been created.
    function policyExists(uint64 policyId) external view returns (bool);

    /// @notice Returns the type and admin of `policyId`. For COMPOUND,
    ///         AND, OR: admin is `address(0)`. For built-ins (0, 1):
    ///         the policy type is implementation-defined (not
    ///         categorized as any concrete type).
    function policyData(uint64 policyId) external view returns (PolicyType policyType, address admin);

    /// @notice Returns the four constituent policy IDs of a COMPOUND
    ///         policy.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is
    ///         not COMPOUND.
    function compoundPolicyData(uint64 policyId)
        external
        view
        returns (
            uint64 senderPolicyId,
            uint64 recipientPolicyId,
            uint64 mintRecipientPolicyId,
            uint64 redeemerPolicyId
        );

    /// @notice Returns the constituent policy IDs of an AND or OR
    ///         combinator. Reverts with `IncompatiblePolicyType` for
    ///         any other type.
    function combinatorPolicyData(uint64 policyId) external view returns (uint64[] memory constituentPolicyIds);

    // ===== future hardfork getters =====

    /// @notice Returns the (`maxAmount`, `interval`) config of a
    ///         RATE_LIMIT policy.
    /// @dev    **Future hardfork.**
    function rateLimitConfig(uint64 policyId) external view returns (uint96 maxAmount, uint40 interval);

    /// @notice Returns the per-address state for `user` on a RATE_LIMIT
    ///         policy. `remaining` is the capacity available right now
    ///         (after replenishment); `lastConsumeTimestamp` is when
    ///         it was last debited.
    /// @dev    **Future hardfork.**
    function rateLimitState(uint64 policyId, address user)
        external
        view
        returns (uint96 remaining, uint40 lastConsumeTimestamp);

    /// @notice Returns the (`perAddress`, `globalUnlockTimestamp`)
    ///         config of a TIME_LOCK policy.
    /// @dev    **Future hardfork.**
    function timeLockConfig(uint64 policyId) external view returns (bool perAddress, uint64 globalUnlockTimestamp);

    /// @notice Returns the per-address unlock timestamp for `user` on
    ///         a per-address TIME_LOCK policy. Returns 0 if no per-
    ///         address unlock is set (and the policy is per-address);
    ///         the caller may interpret 0 as "no unlock configured"
    ///         depending on the policy's intended semantic.
    /// @dev    **Future hardfork.**
    function timeLockUnlock(uint64 policyId, address user) external view returns (uint64 unlockAt);

    /// @notice Returns the default `maxPerTx` of an AMOUNT_CAP policy.
    /// @dev    **Future hardfork.**
    function amountCapConfig(uint64 policyId) external view returns (uint256 maxPerTx);

    /// @notice Returns the per-address override for `user` on an
    ///         AMOUNT_CAP policy. Returns 0 if no override is set
    ///         (user falls back to the default `maxPerTx`).
    /// @dev    **Future hardfork.**
    function amountCapOverride(uint64 policyId, address user) external view returns (uint256 maxPerTx);
}
