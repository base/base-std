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

    /// @notice Policy type discriminator.
    ///
    /// @param BLOCKLIST Authorized unless in the policy's set.
    /// @param ALLOWLIST Authorized only if in the policy's set.
    enum PolicyType {
        BLOCKLIST,
        ALLOWLIST
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

    /*//////////////////////////////////////////////////////////////
                            POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new policy with no initial members. Permissionless.
    ///
    /// @dev Reverts with `ZeroAddress` when `admin` is `address(0)`.
    /// @dev Panics with arithmetic overflow (Panic 0x11) when the policy counter has reached its maximum value.
    ///
    /// @param admin      Initial admin authorized to modify membership and transfer or renounce administration.
    /// @param policyType BLOCKLIST or ALLOWLIST.
    ///
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Creates a new policy seeded with `accounts` as initial members. Permissionless.
    ///
    /// @dev Reverts with `ZeroAddress` when `admin` is `address(0)`. Takes precedence over `BatchSizeTooLarge`.
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
