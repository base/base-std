// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IPolicyRegistry
///
/// @notice Singleton registry of address-membership policies. Policies are referenced by
///         `uint64 policyId` and queried via `isAuthorized(policyId, account)`.
interface IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy type discriminator. Discriminants are append-only: BLOCKLIST and ALLOWLIST
    ///         keep values 0 and 1, so the composite gates ride the policy ID top byte without
    ///         shifting the existing leaf types.
    ///
    /// @param BLOCKLIST Leaf. Authorized unless in the policy's set.
    /// @param ALLOWLIST Leaf. Authorized only if in the policy's set.
    /// @param UNION     Composite. Authorized if authorized under ANY operand (logical OR).
    /// @param INTERSECT Composite. Authorized only if authorized under EVERY operand (logical AND).
    enum PolicyType {
        BLOCKLIST,
        ALLOWLIST,
        UNION,
        INTERSECT
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH was attached to a call targeting a nonpayable policy registry selector.
    ///
    /// @dev The precompile checks `msg.value != 0` at the top of dispatch before any other
    ///      validation. All policy registry selectors are nonpayable.
    error NonPayable();

    /// @notice Caller is not the admin required by the attempted operation.
    error Unauthorized();

    /// @notice The referenced policy ID does not exist.
    error PolicyNotFound();

    /// @notice The operation is incompatible with the policy's type.
    error IncompatiblePolicyType();

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /// @notice A membership batch exceeded the registry limit.
    /// @param maxBatchSize Maximum number of accounts permitted per call.
    error BatchSizeTooLarge(uint256 maxBatchSize);

    /// @notice `finalizeUpdateAdmin` was called with no pending admin staged.
    error NoPendingAdmin();

    /// @notice A composite policy was created or updated with an empty operand set. A composite must
    ///         reference at least one operand, so the never-revert fold evaluator need not define
    ///         empty-UNION / empty-INTERSECT semantics.
    error EmptyOperandSet();

    /// @notice A composite operand is not a flat leaf. Operands must be existing ALLOWLIST or
    ///         BLOCKLIST policies; a composite may not reference another composite (flat-only).
    /// @param operandId The offending operand policy ID.
    error InvalidOperand(uint64 operandId);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A new policy was created.
    event PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType);

    /// @notice A new admin was staged. `pendingAdmin == address(0)` clears a prior nomination.
    event PolicyAdminStaged(uint64 indexed policyId, address indexed currentAdmin, address indexed pendingAdmin);

    /// @notice The active admin changed. `newAdmin == address(0)` indicates renunciation;
    ///         `previousAdmin == address(0)` indicates initial assignment at creation.
    event PolicyAdminUpdated(uint64 indexed policyId, address indexed previousAdmin, address indexed newAdmin);

    /// @notice One or more accounts had their ALLOWLIST membership set to `allowed` in a single batch.
    event AllowlistUpdated(uint64 indexed policyId, address indexed updater, bool allowed, address[] accounts);

    /// @notice One or more accounts had their BLOCKLIST membership set to `blocked` in a single batch.
    event BlocklistUpdated(uint64 indexed policyId, address indexed updater, bool blocked, address[] accounts);

    /// @notice A composite policy (UNION or INTERSECT) was created over `operands`.
    event CompositePolicyCreated(
        uint64 indexed policyId, address indexed creator, PolicyType policyType, uint64[] operands
    );

    /// @notice A composite policy's operand set was replaced in full with `operands`. The event
    ///         carries the complete post-update set, so an indexer reconstructs current state from a
    ///         single log with no delta folding.
    event CompositeOperandsUpdated(uint64 indexed policyId, address indexed updater, uint64[] operands);

    /*//////////////////////////////////////////////////////////////
                            POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new leaf policy with no initial members. Permissionless.
    ///
    /// @dev Reverts with `ZeroAddress` when `admin` is `address(0)`.
    /// @dev Reverts with `IncompatiblePolicyType` when `policyType` is a composite gate (UNION or
    ///      INTERSECT); use `createCompositePolicy` for those.
    /// @dev Panics with arithmetic overflow (Panic 0x11) when the policy counter has reached its maximum value.
    ///
    /// @param admin      Initial admin authorized to modify membership and transfer or renounce administration.
    /// @param policyType BLOCKLIST or ALLOWLIST.
    ///
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Creates a new leaf policy seeded with `accounts` as initial members. Permissionless.
    ///
    /// @dev Reverts with `ZeroAddress` when `admin` is `address(0)`. Takes precedence over `BatchSizeTooLarge`.
    /// @dev Reverts with `IncompatiblePolicyType` when `policyType` is a composite gate (UNION or
    ///      INTERSECT); use `createCompositePolicy` for those. Takes precedence over `BatchSizeTooLarge`.
    /// @dev Reverts with `BatchSizeTooLarge` when `accounts.length` exceeds the registry limit.
    /// @dev Panics with arithmetic overflow (Panic 0x11) when the policy counter has reached its maximum value.
    ///
    /// @param admin      Initial admin authorized to modify membership and transfer or renounce administration.
    /// @param policyType BLOCKLIST or ALLOWLIST.
    /// @param accounts   Initial member set.
    ///
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId);

    /// @notice Creates a new composite policy that combines existing leaf policies under a logic gate.
    ///         Permissionless. A UNION authorizes an account if ANY operand authorizes it; an INTERSECT
    ///         authorizes only if EVERY operand does. `isAuthorized` folds the operands and never reverts.
    ///
    /// @dev Operands are flat-only: each must be an existing ALLOWLIST or BLOCKLIST policy, never another
    ///      composite. Because operands reference smaller, already-assigned IDs, the reference graph is a
    ///      DAG and cannot cycle. The operand set is capped at the composite operand limit.
    /// @dev Reverts with `IncompatiblePolicyType` when `gate` is not UNION or INTERSECT.
    /// @dev Reverts with `ZeroAddress` when `admin` is `address(0)`.
    /// @dev Reverts with `EmptyOperandSet` when `operands` is empty.
    /// @dev Reverts with `BatchSizeTooLarge` when `operands.length` exceeds the composite operand limit.
    /// @dev Reverts with `PolicyNotFound` when any operand does not exist.
    /// @dev Reverts with `InvalidOperand` when any operand is itself a composite (not a flat leaf).
    /// @dev Panics with arithmetic overflow (Panic 0x11) when the policy counter has reached its maximum value.
    ///
    /// @param admin    Initial admin authorized to update operands and transfer or renounce administration.
    /// @param gate     UNION or INTERSECT.
    /// @param operands Existing leaf policy IDs to combine.
    ///
    /// @return newPolicyId The newly assigned composite policy ID.
    function createCompositePolicy(address admin, PolicyType gate, uint64[] calldata operands)
        external
        returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                          POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Stages a proposed new admin for `policyId`. The active admin does not change
    ///         until `pendingAdmin` calls `finalizeUpdateAdmin`.
    ///
    /// @dev Reverts with `PolicyNotFound` when `policyId` does not exist.
    /// @dev Reverts with `Unauthorized` when the caller is not the current admin.
    ///
    /// @param policyId Policy whose admin is being staged.
    /// @param newAdmin Proposed new admin, or `address(0)` to clear any pending nomination.
    function stageUpdateAdmin(uint64 policyId, address newAdmin) external;

    /// @notice Completes a two-step admin transfer. Promotes the caller to active admin and clears the pending slot.
    ///
    /// @dev Reverts with `PolicyNotFound` when `policyId` does not exist.
    /// @dev Reverts with `NoPendingAdmin` when no transfer is in flight.
    /// @dev Reverts with `Unauthorized` when the caller is not the staged pending admin.
    ///
    /// @param policyId Policy whose admin transfer is being finalized.
    function finalizeUpdateAdmin(uint64 policyId) external;

    /// @notice Permanently relinquishes administration of `policyId`. The member set is frozen
    ///         and the policy can never be re-administered; `isAuthorized` queries continue to work.
    ///
    /// @dev Reverts with `PolicyNotFound` when `policyId` does not exist.
    /// @dev Reverts with `Unauthorized` when the caller is not the current admin.
    ///
    /// @param policyId Policy whose administration is being renounced.
    function renounceAdmin(uint64 policyId) external;

    /// @notice Sets `accounts` membership in an ALLOWLIST policy to `allowed` in one batch.
    ///
    /// @dev Reverts with `PolicyNotFound` when `policyId` does not exist.
    /// @dev Reverts with `IncompatiblePolicyType` when the policy is not ALLOWLIST.
    /// @dev Reverts with `Unauthorized` when the caller is not the current admin.
    /// @dev Reverts with `BatchSizeTooLarge` when `accounts.length` exceeds the registry limit.
    ///
    /// @param policyId Policy to update.
    /// @param allowed  Membership state to apply to every account in the batch.
    /// @param accounts Accounts to update.
    function updateAllowlist(uint64 policyId, bool allowed, address[] calldata accounts) external;

    /// @notice Sets `accounts` membership in a BLOCKLIST policy to `blocked` in one batch.
    ///
    /// @dev Reverts with `PolicyNotFound` when `policyId` does not exist.
    /// @dev Reverts with `IncompatiblePolicyType` when the policy is not BLOCKLIST.
    /// @dev Reverts with `Unauthorized` when the caller is not the current admin.
    /// @dev Reverts with `BatchSizeTooLarge` when `accounts.length` exceeds the registry limit.
    ///
    /// @param policyId Policy to update.
    /// @param blocked  Membership state to apply to every account in the batch.
    /// @param accounts Accounts to update.
    function updateBlocklist(uint64 policyId, bool blocked, address[] calldata accounts) external;

    /// @notice Replaces a composite policy's operand set in full with `operands`. The caller sends the
    ///         complete desired operand list, and it is re-validated as at creation. The gate (UNION or
    ///         INTERSECT) is fixed in the policy ID and cannot change; a different gate requires a new
    ///         composite.
    ///
    /// @dev Overwrite semantics are last-write-wins. The function carries no expected-version guard, so
    ///      concurrent full-set submissions by shared admins overwrite one another with no conflict
    ///      signal; serialize edits through the governing multisig or approval flow, and read the
    ///      current operands before editing.
    /// @dev Guard order: `PolicyNotFound` -> `IncompatiblePolicyType` -> `Unauthorized` ->
    ///      `EmptyOperandSet` / `BatchSizeTooLarge` -> per-operand `PolicyNotFound` / `InvalidOperand`.
    /// @dev Reverts with `PolicyNotFound` when `policyId` does not exist.
    /// @dev Reverts with `IncompatiblePolicyType` when `policyId` is not a composite (UNION or INTERSECT).
    /// @dev Reverts with `Unauthorized` when the caller is not the current admin. A renounced composite
    ///      (admin `address(0)`) can never be updated.
    /// @dev Reverts with `EmptyOperandSet` when `operands` is empty; there is no clear-the-list path.
    /// @dev Reverts with `BatchSizeTooLarge` when `operands.length` exceeds the composite operand limit.
    /// @dev Reverts with `PolicyNotFound` when any operand does not exist.
    /// @dev Reverts with `InvalidOperand` when any operand is itself a composite (not a flat leaf).
    ///
    /// @param policyId Composite policy to update.
    /// @param operands Complete new operand set of existing leaf policy IDs.
    function updateCompositeOperands(uint64 policyId, uint64[] calldata operands) external;

    /*//////////////////////////////////////////////////////////////
                         AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns whether `account` is authorized under `policyId`. Never reverts; unknown
    ///         or malformed IDs collapse to empty-member-set semantics (ALLOWLIST -> false,
    ///         BLOCKLIST -> true).
    ///
    /// @dev Callers that store policy IDs MUST validate `policyExists(policyId)` at write time.
    ///
    /// @param policyId Policy to query.
    /// @param account  Account to check.
    ///
    /// @return Whether `account` is authorized.
    function isAuthorized(uint64 policyId, address account) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns whether `policyId` is a built-in sentinel or a previously-assigned custom ID. Never reverts.
    ///
    /// @param policyId Policy to query.
    ///
    /// @return Whether the policy exists.
    function policyExists(uint64 policyId) external view returns (bool);

    /// @notice Returns the current admin of `policyId`, or `address(0)` for built-in sentinels,
    ///         renounced policies, unknown IDs, and malformed IDs. Never reverts.
    ///
    /// @param policyId Policy to query.
    ///
    /// @return Current admin, or `address(0)`.
    function policyAdmin(uint64 policyId) external view returns (address);

    /// @notice Returns the currently-staged pending admin for `policyId`, or `address(0)` when
    ///         no transfer is in flight or for built-in sentinels, unknown IDs, and malformed IDs.
    ///         Never reverts.
    ///
    /// @param policyId Policy to query.
    ///
    /// @return Pending admin, or `address(0)`.
    function pendingPolicyAdmin(uint64 policyId) external view returns (address);
}
