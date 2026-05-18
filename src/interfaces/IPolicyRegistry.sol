// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IPolicyRegistry
/// @notice Singleton registry of transfer-authorization policies for B-20
///         tokens. Each B-20 token holds a single `transferPolicyId`
///         pointing into this registry; on every transfer or mint, the
///         token consults the registry to determine whether the involved
///         addresses are authorized.
///
///         Two policy types are supported in v1:
///         - ALLOWLIST: only listed addresses are authorized.
///         - BLOCKLIST: all addresses except listed ones are authorized.
///
/// @dev    Adapted from Tempo TIP-403 + TIP-1015 with three deliberate
///         omissions: no virtual-address rejection logic (no TIP-1022 on
///         Base), no receive policies (no TIP-1028 escrow), no callback /
///         richer guard policies (could be added in a future hardfork).
///
///         The registry is a singleton at a fixed precompile address. All
///         B-20 tokens on the chain reference the same `policyId` namespace.
///         Anyone may create policies; the creator picks the admin
///         (typically themselves or a multisig).
///
///         Built-in policy IDs (always present, never need to be created):
///         - `0` — always-reject. All authorization queries return false.
///                  Useful as the safe default for newly created tokens
///                  that should not transfer until compliance is configured,
///                  and as a "kill switch" independent of pause state.
///         - `1` — always-allow. All authorization queries return true.
///                  Useful for tokens that opt out of compliance gating.
///
///         Custom policy IDs start at 2 and are assigned monotonically by
///         `nextPolicyId`.
interface IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy type discriminator.
    /// @param ALLOWLIST An address is authorized only if it is in the policy's set.
    /// @param BLOCKLIST An address is authorized unless it is in the policy's set.
    enum PolicyType {
        ALLOWLIST,
        BLOCKLIST
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the policy admin.
    error Unauthorized();

    /// @notice The referenced policy ID does not exist (and is not built-in).
    error PolicyNotFound();

    /// @notice The operation is incompatible with the policy's type. For
    ///         example, calling `updatePolicyAllowlist` on a BLOCKLIST policy.
    error IncompatiblePolicyType();

    /// @notice The provided policy type value is not in the `PolicyType` enum.
    error InvalidPolicyType();

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new policy is created.
    event PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType);

    /// @notice Emitted when a policy's admin is updated (including initial
    ///         assignment at creation).
    event PolicyAdminUpdated(uint64 indexed policyId, address indexed updater, address indexed admin);

    /// @notice Emitted when an account's status is updated for an ALLOWLIST policy.
    event AllowlistUpdated(uint64 indexed policyId, address indexed updater, bool allowed, address[] account);

    /// @notice Emitted when an account's status is updated for a BLOCKLIST policy.
    event BlocklistUpdated(uint64 indexed policyId, address indexed updater, bool blocked, address[] account);

    /*//////////////////////////////////////////////////////////////
                            POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new policy.
    /// @dev    Permissionless. Reverts with `ZeroAddress` if `admin` is
    ///         `address(0)`, and with `InvalidPolicyType` if `policyType`
    ///         is not a valid `PolicyType` enum value.
    /// @param admin       The address authorized to modify this policy.
    /// @param policyType  ALLOWLIST or BLOCKLIST.
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Same as `createPolicy`, but additionally seeds the policy's
    ///         member set with `accounts`. Convenience for one-shot
    ///         creation flows that don't need an empty initial state.
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                          POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers admin rights for a policy. Caller must be the
    ///         current admin.
    function updatePolicyAdmin(uint64 policyId, address newAdmin) external;

    /// @notice Adds or removes `accounts` from an ALLOWLIST policy, all
    ///         receiving the same `allowed` setting. Caller must be the
    ///         policy admin.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         ALLOWLIST. Emits one `AllowlistUpdated` event per account.
    function updatePolicyAllowlist(uint64 policyId, bool allowed, address[] calldata accounts) external;

    /// @notice Adds or removes `accounts` from a BLOCKLIST policy, all
    ///         receiving the same `blocked` setting. Caller must be the
    ///         policy admin.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         BLOCKLIST. Emits one `BlocklistUpdated` event per account.
    function updatePolicyBlocklist(uint64 policyId, bool blocked, address[] calldata accounts) external;

    /*//////////////////////////////////////////////////////////////
                         AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether `user` is authorized under `policyId`. For an
    ///         ALLOWLIST policy, returns true iff `user` is in the set.
    ///         For a BLOCKLIST policy, returns true iff `user` is NOT in
    ///         the set. Built-in ID `0` always returns false; ID `1`
    ///         always returns true.
    function isAuthorized(uint64 policyId, address user) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The next policy ID that will be assigned by `createPolicy` /
    ///         `createPolicyWithAccounts`. Starts at 2 (IDs 0 and 1 are
    ///         reserved for the built-ins).
    function nextPolicyId() external view returns (uint64);

    /// @notice Whether `policyId` exists. The built-in IDs (0, 1) always
    ///         exist; custom IDs (>=2) exist iff they have been created.
    function policyExists(uint64 policyId) external view returns (bool);

    /// @notice The type of `policyId`.
    ///         Reverts with `PolicyNotFound` for unknown policy IDs.
    function policyType(uint64 policyId) external view returns (PolicyType);

    /// @notice The admin address for `policyId`. Returns `address(0)` for
    ///         built-in policies (which have no admin).
    ///         Reverts with `PolicyNotFound` for unknown policy IDs.
    function policyAdmin(uint64 policyId) external view returns (address);
}
