// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IPolicyRegistry
/// @notice Singleton registry of address-membership policies. B-20 tokens
///         reference policies in this registry by `uint64 policyId` to
///         enforce authorization at the protocol level: every transfer,
///         mint, and redeem on a B-20 token resolves to one or more
///         `isAuthorized(policyId, account)` calls into this registry.
///
///         Two policy types are supported in v1:
///         - **ALLOWLIST**: an account is authorized only if it is on the
///           policy's member set.
///         - **BLOCKLIST**: an account is authorized unless it is on the
///           policy's member set.
///
///         The registry deliberately stops at flat membership checks.
///         There is no on-registry composition (no AND/OR/COMPOUND),
///         no callback or richer guard policies, no amount conditioning.
///         Asymmetric per-role rules on a token are expressed by storing
///         multiple policy IDs on the token itself (one per role slot),
///         not by composing inside the registry. See `IB20`'s policy
///         model for how this is wired on the token side.
///
/// @dev    The registry is a singleton precompile at a fixed address.
///         All B-20 tokens on the chain share the same `policyId`
///         namespace. Anyone may create a policy; the creator nominates
///         the policy admin (typically themselves or a multisig).
///
///         **Built-in policy IDs** (always present, never need to be
///         created):
///         - `0` — always-allow. `isAuthorized(0, any)` returns true.
///                  Semantic: "there is no policy on this slot." This is
///                  the default state of every unassigned policy slot on
///                  a newly created token, matching the principle that
///                  absence of a configured policy means no restriction.
///         - `1` — always-block. `isAuthorized(1, any)` returns false.
///                  Useful as an explicit hard-deny on a policy slot
///                  (e.g. disabling redemption by pointing `REDEEMER_SENDER_POLICY`
///                  at this ID), or as a kill switch independent of
///                  token-level pause.
///
///         **Policy ID encoding.** Custom policy IDs encode the policy's
///         type directly into the top byte of the ID, so `policyType(id)`
///         resolves via pure bit extraction with no SLOAD. Since every
///         B-20 transfer / mint / redeem consults the registry, removing
///         a per-call storage read from the type lookup is a material
///         protocol-wide saving.
///
///         Encoding layout for custom IDs:
///         ```
///         [63:56]  uint8 type discriminator = uint8(PolicyType)
///         [55:0]   uint56 global counter (max ~7.2e16)
///         ```
///         Discriminators currently in use:
///         - `0x00` — ALWAYS_ALLOW (reserved; no custom policies carry this discriminator)
///         - `0x01` — ALWAYS_BLOCK (reserved; no custom policies carry this discriminator)
///         - `0x02` — ALLOWLIST
///         - `0x03` — BLOCKLIST
///         - `0x04` .. `0xFF` — reserved for future PolicyType enum values
///
///         The two built-in IDs (`0` and `1`) are special-cased BEFORE
///         the encoding is consulted: implementations short-circuit on
///         those exact ID values. The ALWAYS_ALLOW and ALWAYS_BLOCK
///         discriminators (`0x00`, `0x01`) are reserved solely for the
///         built-ins; no custom policies are ever assigned IDs with those
///         top bytes, so there is no ambiguity at evaluation time.
///
///         This encoding gives `isAuthorized(policyId, account)` a
///         best-case hot path of 1 SLOAD (the member set), compared to 2
///         SLOADs if the type required a separate storage lookup. The
///         built-in IDs cost 0 SLOADs (short-circuited).
///
///         Separately from `policyId` encoding, implementations store mutable
///         per-policy state (notably admin) in policy-record storage keyed by
///         `policyId`; admin is not encoded into the ID itself.
///
///         Custom policy IDs are assigned from a single global monotonic
///         counter starting at `2` (reserving `0` and `1` for the
///         built-ins); see `nextPolicyId(PolicyType)` to predict the
///         next ID for a given type.
///
///         **Future extensions** (not in v1 scope, intended path):
///         - Union / intersect policies: compose two same-typed policies
///           into a derived membership check. Would be added as new
///           `PolicyType` enum values with sibling `createUnionPolicy` /
///           `createIntersectPolicy` creators. Enum extension is
///           backward-compatible; existing policies and consumers stay
///           valid. Defer to a future hardfork.
interface IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy type discriminator.
    /// @param ALWAYS_ALLOW Built-in always-allow type; corresponds to policy ID `0`.
    /// @param ALWAYS_BLOCK Built-in always-block type; corresponds to policy ID `1`.
    /// @param ALLOWLIST    An account is authorized only if it is in the policy's set.
    /// @param BLOCKLIST    An account is authorized unless it is in the policy's set.
    enum PolicyType {
        ALWAYS_ALLOW,
        ALWAYS_BLOCK,
        ALLOWLIST,
        BLOCKLIST
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the policy admin (where current admin is
    ///         required) or is not the pending admin (where pending admin
    ///         is required by `finalizeUpdateAdmin`).
    error Unauthorized();

    /// @notice The referenced policy ID does not exist (and is not built-in).
    error PolicyNotFound();

    /// @notice The provided `uint64 policyId` is malformed: its top byte
    ///         (the `PolicyType` discriminator) is outside the
    ///         `PolicyType` enum range (i.e. greater than
    ///         `uint8(type(PolicyType).max)`). Reverted by every entry
    ///         point that accepts a `policyId`, distinct from
    ///         `PolicyNotFound` (which fires for well-formed IDs that
    ///         simply haven't been created).
    error MalformedPolicyId(uint64 policyId);

    /// @notice The operation is incompatible with the policy's type. For
    ///         example, calling `updateAllowlist` on a BLOCKLIST policy.
    error IncompatiblePolicyType();

    /// @notice The provided policy type value is not in the `PolicyType` enum.
    error InvalidPolicyType();

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /// @notice `finalizeUpdateAdmin` was called for a policy with no
    ///         currently-staged pending admin.
    error NoPendingAdmin();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A new policy was created. The creator may or may not be the
    ///         policy admin (the admin is set explicitly at creation).
    event PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType);

    /// @notice A new admin was staged via `stageUpdateAdmin`. The active
    ///         admin does not change until `finalizeUpdateAdmin` is called
    ///         by `pendingAdmin`. `pendingAdmin == address(0)` indicates
    ///         a previously-staged transfer was cleared.
    event PolicyAdminStaged(uint64 indexed policyId, address indexed currentAdmin, address indexed pendingAdmin);

    /// @notice The active admin actually changed: either via
    ///         `finalizeUpdateAdmin` (where `newAdmin` is the previously
    ///         pending admin) or via `renounceAdmin` (where
    ///         `newAdmin == address(0)`). Initial admin assignment at
    ///         policy creation is also emitted as a `PolicyAdminUpdated`
    ///         with `previousAdmin == address(0)`.
    event PolicyAdminUpdated(uint64 indexed policyId, address indexed previousAdmin, address indexed newAdmin);

    /// @notice One or more accounts had their ALLOWLIST membership set to
    ///         `allowed`. Emitted once per `updateAllowlist` call, carrying
    ///         the full batch.
    event AllowlistUpdated(uint64 indexed policyId, address indexed updater, bool allowed, address[] accounts);

    /// @notice One or more accounts had their BLOCKLIST membership set to
    ///         `blocked`. Emitted once per `updateBlocklist` call, carrying
    ///         the full batch.
    event BlocklistUpdated(uint64 indexed policyId, address indexed updater, bool blocked, address[] accounts);

    /*//////////////////////////////////////////////////////////////
                            POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new policy with no initial members.
    /// @dev    Permissionless. Reverts with `ZeroAddress` if `admin` is
    ///         `address(0)`, and with `InvalidPolicyType` if `policyType`
    ///         is not a valid `PolicyType` enum value.
    /// @param admin       The address authorized to modify membership on
    ///                    this policy and to transfer or renounce
    ///                    administration.
    /// @param policyType  ALLOWLIST or BLOCKLIST.
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Same as `createPolicy`, but seeds the policy's member set
    ///         with `accounts` in a single call. Useful for one-shot
    ///         creation flows that ship with a non-empty initial state.
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                          POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Stages a proposed new admin for `policyId`. Caller MUST be
    ///         the current admin. The active admin does NOT change until
    ///         `pendingAdmin` calls `finalizeUpdateAdmin(policyId)`.
    /// @dev    Calling `stageUpdateAdmin` while a pending admin already
    ///         exists overwrites the prior nomination (the previously
    ///         pending admin loses their ability to finalize). Pass
    ///         `address(0)` to clear a previously-staged transfer
    ///         without nominating a new candidate.
    ///
    ///         Two-step transfer guards against typos and key compromise:
    ///         the candidate must actively claim the role, and the
    ///         current admin retains control until they do.
    /// @param policyId  The policy whose admin is being staged.
    /// @param newAdmin  The proposed new admin, or `address(0)` to clear.
    function stageUpdateAdmin(uint64 policyId, address newAdmin) external;

    /// @notice Completes a two-step admin transfer. Caller MUST be the
    ///         address most recently staged via `stageUpdateAdmin`.
    ///         Promotes the caller to active admin and clears the pending
    ///         slot. Reverts with `NoPendingAdmin` if no transfer is in
    ///         flight.
    function finalizeUpdateAdmin(uint64 policyId) external;

    /// @notice Single-step: the current admin permanently relinquishes
    ///         administration of `policyId`. Caller MUST be the current
    ///         admin. After this call, `policyAdmin(policyId)` returns
    ///         `address(0)` and no further admin-gated operations on this
    ///         policy can succeed: the policy's member set is frozen
    ///         forever, and the policy can never be re-administered.
    /// @dev    Any in-flight pending admin (set via `stageUpdateAdmin`)
    ///         is cleared as a side effect of renunciation. The policy
    ///         continues to exist and remains a valid target of
    ///         `isAuthorized` queries; only mutation is disabled.
    function renounceAdmin(uint64 policyId) external;

    /// @notice Adds or removes `accounts` from an ALLOWLIST policy. All
    ///         accounts receive the same `allowed` setting in one batch.
    ///         Caller MUST be the current policy admin.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         ALLOWLIST. Emits a single `AllowlistUpdated` event
    ///         carrying the full batch.
    function updateAllowlist(uint64 policyId, bool allowed, address[] calldata accounts) external;

    /// @notice Adds or removes `accounts` from a BLOCKLIST policy. All
    ///         accounts receive the same `blocked` setting in one batch.
    ///         Caller MUST be the current policy admin.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         BLOCKLIST. Emits a single `BlocklistUpdated` event
    ///         carrying the full batch.
    function updateBlocklist(uint64 policyId, bool blocked, address[] calldata accounts) external;

    /*//////////////////////////////////////////////////////////////
                         AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `account` is authorized under `policyId`.
    ///         - For ALLOWLIST: returns true iff `account` is on the
    ///           policy's member set.
    ///         - For BLOCKLIST: returns true iff `account` is NOT on the
    ///           policy's member set.
    ///         - For built-in ID `0` (always-allow): always returns true.
    ///         - For built-in ID `1` (always-block): always returns false.
    /// @dev    Reverts with `PolicyNotFound` if `policyId` is neither a
    ///         built-in nor a previously-created policy.
    function isAuthorized(uint64 policyId, address account) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The full policy ID that would be assigned by the next
    ///         `createPolicy(admin, policyType)` call. Encodes `policyType`
    ///         into the top byte combined with the current global counter
    ///         in the low 56 bits. The counter starts at `2` and increments
    ///         by one per policy created, regardless of type.
    function nextPolicyId(PolicyType policyType) external view returns (uint64);

    /// @notice Whether `policyId` exists. Returns true for built-in IDs
    ///         `0` and `1`, and for any custom policy ID previously
    ///         assigned by `createPolicy` or `createPolicyWithAccounts`.
    function policyExists(uint64 policyId) external view returns (bool);

    /// @notice The type of `policyId`. Returns `PolicyType.ALWAYS_ALLOW`
    ///         for built-in ID `0`, `PolicyType.ALWAYS_BLOCK` for built-in
    ///         ID `1`, or the stored type for custom IDs. Reverts with
    ///         `PolicyNotFound` for unknown IDs.
    function policyType(uint64 policyId) external view returns (PolicyType);

    /// @notice The current admin of `policyId`. Returns `address(0)` for
    ///         built-in policies (which have no admin) and for policies
    ///         whose admin has been renounced via `renounceAdmin`.
    ///         Reverts with `PolicyNotFound` for unknown IDs.
    function policyAdmin(uint64 policyId) external view returns (address);

    /// @notice The currently-staged pending admin for `policyId`, set by
    ///         the most recent `stageUpdateAdmin` and cleared on
    ///         `finalizeUpdateAdmin` or `renounceAdmin`. Returns
    ///         `address(0)` when no transfer is in flight. Always
    ///         `address(0)` for built-in policies.
    function pendingPolicyAdmin(uint64 policyId) external view returns (address);
}
