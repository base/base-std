// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title IPolicyRegistry
/// @notice Singleton registry of transfer-authorization policies for B-20
///         tokens. Each B-20 token holds a single `transferPolicyId`
///         pointing into this registry; on every transfer or mint, the
///         token consults the registry to determine whether the involved
///         addresses are authorized.
///
///         Three policy types are supported in v1:
///         - WHITELIST: only listed addresses are authorized.
///         - BLACKLIST: all addresses except listed ones are authorized.
///         - COMPOUND: references three simple policies, one for senders,
///           one for recipients, one for mint recipients. Lets a single
///           policy ID carry asymmetric rules.
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
///                  Useful for tokens that opt out of compliance gating,
///                  and as the identity element in compound policies.
///
///         Custom policy IDs start at 2 and are assigned monotonically by
///         `policyIdCounter`.
interface IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Policy type discriminator.
    /// @param WHITELIST An address is authorized only if it is in the policy's set.
    /// @param BLACKLIST An address is authorized unless it is in the policy's set.
    /// @param COMPOUND  The policy carries no member set of its own. It
    ///                  references three simple policies and delegates the
    ///                  per-role check.
    enum PolicyType {
        WHITELIST,
        BLACKLIST,
        COMPOUND
    }

    /// @notice Top-level data for any policy (simple or compound).
    /// @param policyType The type of the policy.
    /// @param admin      The address that may modify this policy. Zero for
    ///                   COMPOUND policies (they are structurally immutable).
    struct PolicyData {
        PolicyType policyType;
        address admin;
    }

    /// @notice Constituent policy IDs for a compound policy.
    /// @param senderPolicyId        Policy checked for transfer senders.
    /// @param recipientPolicyId     Policy checked for transfer recipients.
    /// @param mintRecipientPolicyId Policy checked for mint recipients.
    struct CompoundPolicyData {
        uint64 senderPolicyId;
        uint64 recipientPolicyId;
        uint64 mintRecipientPolicyId;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the policy admin.
    error Unauthorized();

    /// @notice The referenced policy ID does not exist (and is not built-in).
    error PolicyNotFound();

    /// @notice A compound policy attempted to reference another compound
    ///         policy as a constituent. Only simple policies (WHITELIST,
    ///         BLACKLIST) and the built-in IDs (0, 1) are valid constituents.
    error PolicyNotSimple();

    /// @notice The operation is incompatible with the policy's type. For
    ///         example, calling `modifyPolicyWhitelist` on a BLACKLIST
    ///         policy, or `compoundPolicyData` on a non-COMPOUND policy.
    error IncompatiblePolicyType();

    /// @notice The provided policy type value is not in the `PolicyType`
    ///         enum, or is not legal for the requested operation (e.g.
    ///         calling `createPolicy` with `COMPOUND`).
    error InvalidPolicyType();

    /// @notice A required address argument was the zero address.
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new simple (WHITELIST or BLACKLIST) policy is
    ///         created. For compound policies, see `CompoundPolicyCreated`.
    event PolicyCreated(uint64 indexed policyId, address indexed creator, PolicyType policyType);

    /// @notice Emitted when a new compound policy is created.
    event CompoundPolicyCreated(
        uint64 indexed policyId,
        address indexed creator,
        uint64 senderPolicyId,
        uint64 recipientPolicyId,
        uint64 mintRecipientPolicyId
    );

    /// @notice Emitted when a policy's admin is updated (including initial
    ///         assignment at creation).
    event PolicyAdminUpdated(uint64 indexed policyId, address indexed updater, address indexed admin);

    /// @notice Emitted when an account's whitelist status is updated for a
    ///         WHITELIST policy.
    event WhitelistUpdated(uint64 indexed policyId, address indexed updater, address indexed account, bool allowed);

    /// @notice Emitted when an account's blacklist status is updated for a
    ///         BLACKLIST policy.
    event BlacklistUpdated(uint64 indexed policyId, address indexed updater, address indexed account, bool restricted);

    /*//////////////////////////////////////////////////////////////
                            POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new simple (WHITELIST or BLACKLIST) policy.
    /// @dev    Permissionless. Reverts with `InvalidPolicyType` if
    ///         `policyType` is `COMPOUND` (use `createCompoundPolicy`),
    ///         and with `ZeroAddress` if `admin` is `address(0)`.
    /// @param admin       The address authorized to modify this policy.
    /// @param policyType  WHITELIST or BLACKLIST.
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Same as `createPolicy`, but additionally seeds the policy's
    ///         member set with `accounts`. Convenience for one-shot
    ///         creation flows that don't need an empty initial state.
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId);

    /// @notice Creates a new compound policy referencing three constituent
    ///         simple policies. Compound policies are structurally
    ///         immutable: the constituent IDs cannot be changed after
    ///         creation, and there is no admin. To rotate the configuration,
    ///         create a new compound policy and re-point the consuming
    ///         token's `transferPolicyId`.
    /// @dev    Permissionless. Each constituent MUST exist and MUST be a
    ///         simple policy (WHITELIST, BLACKLIST) OR a built-in (IDs 0
    ///         or 1). Reverts with `PolicyNotFound` for unknown IDs and
    ///         `PolicyNotSimple` if any constituent is itself COMPOUND.
    function createCompoundPolicy(uint64 senderPolicyId, uint64 recipientPolicyId, uint64 mintRecipientPolicyId)
        external
        returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                          POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers admin rights for a simple policy. Caller must be
    ///         the current admin. Reverts on COMPOUND policies (they have
    ///         no admin).
    function setPolicyAdmin(uint64 policyId, address newAdmin) external;

    /// @notice Adds or removes an account from a WHITELIST policy. Caller
    ///         must be the policy admin.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         WHITELIST.
    function modifyPolicyWhitelist(uint64 policyId, address account, bool allowed) external;

    /// @notice Adds or removes an account from a BLACKLIST policy. Caller
    ///         must be the policy admin.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         BLACKLIST.
    function modifyPolicyBlacklist(uint64 policyId, address account, bool restricted) external;

    /*//////////////////////////////////////////////////////////////
                         AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Composite check returning `isAuthorizedSender(p, u) &&
    ///         isAuthorizedRecipient(p, u)`. Provided for callers that
    ///         want a single-call answer to "is `user` authorized for
    ///         both directions under this policy."
    function isAuthorized(uint64 policyId, address user) external view returns (bool);

    /// @notice Whether `user` is authorized as a transfer sender under
    ///         `policyId`. For simple policies this is equivalent to a
    ///         single membership check; for compound policies it delegates
    ///         to the policy's `senderPolicyId`.
    function isAuthorizedSender(uint64 policyId, address user) external view returns (bool);

    /// @notice Whether `user` is authorized as a transfer recipient under
    ///         `policyId`. For compound policies it delegates to the
    ///         policy's `recipientPolicyId`.
    function isAuthorizedRecipient(uint64 policyId, address user) external view returns (bool);

    /// @notice Whether `user` is authorized as a mint recipient under
    ///         `policyId`. Distinct from `isAuthorizedRecipient` for
    ///         compound policies, which carry separate sender / recipient
    ///         / mint-recipient slots. For simple policies this returns
    ///         the same result as `isAuthorizedRecipient`.
    function isAuthorizedMintRecipient(uint64 policyId, address user) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice The next policy ID that will be assigned by `createPolicy` /
    ///         `createPolicyWithAccounts` / `createCompoundPolicy`. Starts
    ///         at 2 (IDs 0 and 1 are reserved for the built-ins).
    function policyIdCounter() external view returns (uint64);

    /// @notice Whether `policyId` exists. The built-in IDs (0, 1) always
    ///         exist; custom IDs (>=2) exist iff they have been created.
    function policyExists(uint64 policyId) external view returns (bool);

    /// @notice Returns the type and admin of `policyId`.
    /// @dev    For COMPOUND policies, `admin` is `address(0)`. For built-in
    ///         policies, `admin` is `address(0)` and `policyType` is
    ///         implementation-defined (the built-ins are not categorized as
    ///         WHITELIST or BLACKLIST since they have no member set).
    ///         Reverts with `PolicyNotFound` for unknown policy IDs.
    function policyData(uint64 policyId) external view returns (PolicyType policyType, address admin);

    /// @notice Returns the constituent policy IDs of a compound policy.
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         COMPOUND, and with `PolicyNotFound` if the policy does not
    ///         exist.
    function compoundPolicyData(uint64 policyId)
        external
        view
        returns (uint64 senderPolicyId, uint64 recipientPolicyId, uint64 mintRecipientPolicyId);
}
