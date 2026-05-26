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
///         **Built-in policy IDs** (always present):
///         - `0` — ALWAYS_ALLOW. Also the default state of every
///                 unassigned policy slot. Reads naturally as an empty
///                 BLOCKLIST (no one blocked → allow all).
///         - `(uint64(ALLOWLIST) << 56) | 1` — ALWAYS_BLOCK. Reads
///                 naturally as an empty ALLOWLIST (no one allowed →
///                 block all). Useful as an explicit hard-deny on a slot.
///
///         **Policy ID encoding.** The top byte is the `PolicyType`
///         discriminator; the low 56 bits are a global counter. Type is
///         recoverable from the ID via pure bit extraction — no SLOAD
///         per call on the B-20 hot path.
///         ```
///         [63:56]  uint8(PolicyType) discriminator
///         [55:0]   counter (built-ins use 0/1; custom IDs start at 2)
///         ```
///         Custom policy IDs are assigned from a single global counter
///         starting at `2` (reserving `0`/`1` for the built-in
///         sentinels). Admin is stored in policy-record storage keyed
///         by `policyId`, NOT in the ID.
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

    /// @notice Policy type discriminator. Order is chosen so each
    ///         built-in sentinel ID reads as a degenerate form of its
    ///         list type: `0` = empty BLOCKLIST = ALWAYS_ALLOW;
    ///         `(ALLOWLIST << 56) | 1` = empty ALLOWLIST = ALWAYS_BLOCK.
    /// @param BLOCKLIST  Authorized unless in the policy's set.
    /// @param ALLOWLIST  Authorized only if in the policy's set.
    enum PolicyType {
        BLOCKLIST,
        ALLOWLIST
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the policy admin (where current admin is
    ///         required) or is not the pending admin (where pending admin
    ///         is required by `finalizeUpdateAdmin`).
    error Unauthorized();

    /// @notice The referenced policy ID does not exist (and is not
    ///         built-in). Reverted by mutating entry points; view
    ///         queries return the "absent" value instead.
    error PolicyNotFound();

    /// @notice The operation is incompatible with the policy's type. For
    ///         example, calling `updateAllowlist` on a BLOCKLIST policy.
    error IncompatiblePolicyType();

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /// @notice A membership batch exceeded the registry limit.
    /// @param maxBatchSize The maximum number of accounts permitted per
    ///        `createPolicyWithAccounts`, `updateAllowlist`, or
    ///        `updateBlocklist` call.
    error BatchSizeTooLarge(uint256 maxBatchSize);

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
    ///         `address(0)`. Out-of-range `policyType` values are
    ///         rejected by ABI decoding before this function body runs.
    /// @param admin       The address authorized to modify membership on
    ///                    this policy and to transfer or renounce
    ///                    administration.
    /// @param policyType  BLOCKLIST or ALLOWLIST.
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
    ///         - For the built-in ALWAYS_BLOCK ID
    ///           (`(uint64(ALLOWLIST) << 56) | 1`): always returns false.
    ///         - For malformed IDs (top byte outside the `PolicyType`
    ///           enum range): returns false. The function never reverts.
    /// @dev    **Precondition: `policyId` must exist.** No existence-check
    ///         SLOAD on the hot path; non-existent IDs collapse to empty-
    ///         member-set semantics (ALLOWLIST → false, BLOCKLIST → true).
    ///         Callers that store policy IDs (notably `IB20.updatePolicy`)
    ///         MUST validate `policyExists` at write time.
    function isAuthorized(uint64 policyId, address account) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `policyId` exists. True for the two built-in
    ///         sentinel IDs and for any custom ID previously assigned.
    ///         False for unknown and malformed IDs. Never reverts.
    function policyExists(uint64 policyId) external view returns (bool);

    /// @notice Current admin of `policyId`. Returns `address(0)` for
    ///         built-in sentinels, renounced policies, unknown IDs, and
    ///         malformed IDs. Never reverts.
    function policyAdmin(uint64 policyId) external view returns (address);

    /// @notice Currently-staged pending admin for `policyId`. Returns
    ///         `address(0)` when no transfer is in flight, and for
    ///         built-in sentinels, unknown IDs, and malformed IDs.
    ///         Never reverts.
    function pendingPolicyAdmin(uint64 policyId) external view returns (address);
}
