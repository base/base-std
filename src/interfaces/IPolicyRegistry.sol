// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPolicyRegistry
/// @author Coinbase
/// @notice Singleton registry of transfer-authorization policies for B-20
///         tokens. Each B-20 token holds a single `transferPolicyId`
///         pointing into this registry; on every transfer, mint, or redeem,
///         the token consults the registry to determine whether the involved
///         addresses are authorized.
///
///         Five policy types are defined:
///         - WHITELIST: only listed addresses are authorized.
///         - BLACKLIST: all addresses except listed ones are authorized.
///         - COMPOUND: references four constituent policies, one each for
///           senders, recipients, mint recipients, and redeemers. Lets a
///           single policy ID carry asymmetric per-role rules.
///         - ALWAYS_REJECT: built-in; all authorization queries return false.
///         - ALWAYS_ALLOW: built-in; all authorization queries return true.
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

    /// @notice Policy type discriminator. ALWAYS_REJECT and ALWAYS_ALLOW are
    ///         reserved for the built-in IDs (0 and 1) and cannot be assigned
    ///         to created policies.
    enum PolicyType {
        WHITELIST, // 0: address-set membership; authorized if in set
        BLACKLIST, // 1: address-set membership; authorized if NOT in set
        COMPOUND, // 2: per-role slots delegating to constituent policies
        ALWAYS_REJECT, // 3: built-in; all authorization queries return false
        ALWAYS_ALLOW // 4: built-in; all authorization queries return true
    }

    /// @notice Constituent policy IDs for a compound policy. Each slot maps to one
    ///         transfer role; the constituent policy is evaluated against the address
    ///         fulfilling that role. Slots may reference any simple policy (WHITELIST,
    ///         BLACKLIST) or a built-in ID. Use ID `1` (always-allow) for any slot
    ///         with no constraint, or `0` (always-reject) to hard-block a role.
    struct CompoundPolicyData {
        /// @dev Policy checked for transfer senders.
        uint64 senderPolicyId;
        /// @dev Policy checked for transfer recipients.
        uint64 recipientPolicyId;
        /// @dev Policy checked for mint recipients.
        uint64 mintRecipientPolicyId;
        /// @dev Policy checked for redeem callers.
        uint64 redeemerPolicyId;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not the policy admin.
    error Unauthorized();

    /// @notice The referenced policy ID does not exist (and is not built-in).
    error PolicyNotFound();

    /// @notice A compound policy attempted to reference another compound policy
    ///         as a constituent. Only WHITELIST, BLACKLIST, and built-in IDs
    ///         (0, 1) are valid constituents.
    error ConstituentIsCompound();

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

    /// @notice The policy ID counter has been exhausted. Custom policy IDs are
    ///         bounded by the on-chain packing format (61 bits, or ~2.3e18 IDs);
    ///         creating one more policy would overflow that bound.
    error PolicyIdOverflow();

    /// @notice The caller is not the pending admin for this policy.
    error NotPendingAdmin();

    /// @notice There is no admin transfer in progress for this policy.
    error NoTransferPending();

    /// @notice The policy has been permanently frozen and can no longer be
    ///         modified (no membership changes, no admin transfers, no further
    ///         freezing). This is a one-way state set by `freezePolicy`.
    error PolicyFrozen();

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
        uint64 mintRecipientPolicyId,
        uint64 redeemerPolicyId
    );

    /// @notice Emitted when a policy's admin is updated (including initial
    ///         assignment at creation and on `acceptPolicyAdminTransfer`).
    event PolicyAdminUpdated(uint64 indexed policyId, address indexed updater, address indexed admin);

    /// @notice Emitted when the current admin nominates a new admin via
    ///         `beginPolicyAdminTransfer`. The transfer does not take effect until
    ///         `pendingAdmin` calls `acceptPolicyAdminTransfer`.
    event PolicyAdminTransferBegun(uint64 indexed policyId, address indexed currentAdmin, address indexed pendingAdmin);

    /// @notice Emitted when an in-flight admin transfer is cancelled by the current
    ///         admin (clearing the pending admin without changing the active admin).
    event PolicyAdminTransferCancelled(
        uint64 indexed policyId, address indexed currentAdmin, address indexed cancelledPendingAdmin
    );

    /// @notice Emitted when a policy is permanently frozen. After this event, the
    ///         policy's membership and admin can no longer be modified.
    event PolicyFrozenEvent(uint64 indexed policyId, address indexed frozenBy);

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
    ///
    /// @dev    Permissionless. Reverts with `InvalidPolicyType` if `policyType`
    ///         is `COMPOUND` (use `createCompoundPolicy`), and with `ZeroAddress`
    ///         if `admin` is `address(0)`.
    ///
    /// @param admin       The address authorized to modify this policy.
    /// @param policyType  WHITELIST or BLACKLIST.
    ///
    /// @return newPolicyId The newly assigned policy ID.
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId);

    /// @notice Same as `createPolicy`, but additionally seeds the policy's
    ///         member set with `accounts`. Convenience for one-shot
    ///         creation flows that don't need an empty initial state.
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId);

    /// @notice Creates a new compound policy referencing four constituent policy IDs,
    ///         one per transfer role. Compound policies are immutable: constituent IDs
    ///         cannot be changed after creation, and there is no admin. To rotate
    ///         the configuration, create a new compound policy and re-point the
    ///         token's `transferPolicyId`.
    ///
    /// @dev    Permissionless. Each constituent MUST exist and MUST NOT be COMPOUND.
    ///         Built-in IDs (0 and 1) are always valid. Reverts with
    ///         `PolicyNotFound` for unknown IDs and `ConstituentIsCompound` if
    ///         any constituent is itself COMPOUND.
    function createCompoundPolicy(
        uint64 senderPolicyId,
        uint64 recipientPolicyId,
        uint64 mintRecipientPolicyId,
        uint64 redeemerPolicyId
    ) external returns (uint64 newPolicyId);

    /*//////////////////////////////////////////////////////////////
                          POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Nominates a new admin for a simple policy. The transfer is two-step:
    ///         this call records `newAdmin` as the pending admin without changing the
    ///         active admin. The nominee must then call `acceptPolicyAdminTransfer`.
    ///
    /// @dev    Caller must be the current admin. Reverts on COMPOUND policies (they
    ///         have no admin) and on frozen policies. Calling this again overwrites
    ///         any previously pending admin for this policy. Pass `address(0)` to
    ///         clear a previously nominated pending admin (equivalent to
    ///         `cancelPolicyAdminTransfer`).
    function beginPolicyAdminTransfer(uint64 policyId, address newAdmin) external;

    /// @notice Completes a two-step admin transfer. Caller must be the address
    ///         previously nominated via `beginPolicyAdminTransfer`. On success,
    ///         the caller becomes the new admin and the pending admin slot is
    ///         cleared.
    function acceptPolicyAdminTransfer(uint64 policyId) external;

    /// @notice Cancels a pending admin transfer without changing the active admin.
    ///         Caller must be the current admin.
    function cancelPolicyAdminTransfer(uint64 policyId) external;

    /// @notice Permanently freezes a policy: after this call, the policy's
    ///         membership cannot be modified, its admin cannot be transferred,
    ///         and it cannot be unfrozen. Compound policies that reference this
    ///         policy as a constituent continue to work; only this policy's own
    ///         membership state is locked.
    ///
    /// @dev    Caller must be the current admin. Reverts on COMPOUND policies and
    ///         on already-frozen policies. Any in-flight admin transfer is
    ///         cleared as a side effect.
    function freezePolicy(uint64 policyId) external;

    /// @notice Adds or removes an account from a WHITELIST policy. Caller
    ///         must be the policy admin.
    ///
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         WHITELIST, and with `PolicyFrozen` if the policy has been frozen.
    function modifyPolicyWhitelist(uint64 policyId, address account, bool allowed) external;

    /// @notice Adds or removes an account from a BLACKLIST policy. Caller
    ///         must be the policy admin.
    ///
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         BLACKLIST, and with `PolicyFrozen` if the policy has been frozen.
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

    /// @notice Whether `user` is authorized as a redeemer under `policyId`.
    ///         For compound policies, delegates to the policy's `redeemerPolicyId`.
    ///         For simple policies, equivalent to `isAuthorizedRecipient`.
    function isAuthorizedRedeemer(uint64 policyId, address user) external view returns (bool);

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

    /// @notice Returns the type and admin of `policyId`. For COMPOUND policies,
    ///         `admin` is `address(0)`. For built-in IDs, `admin` is `address(0)`
    ///         and `policyType` is `ALWAYS_REJECT` (ID 0) or `ALWAYS_ALLOW` (ID 1).
    ///         Reverts with `PolicyNotFound` for unknown policy IDs.
    function policyData(uint64 policyId) external view returns (PolicyType policyType, address admin);

    /// @notice The pending admin nominated via `beginPolicyAdminTransfer`, or
    ///         `address(0)` if no transfer is in flight. Always `address(0)`
    ///         for compound and built-in policies.
    function pendingPolicyAdmin(uint64 policyId) external view returns (address);

    /// @notice Whether `policyId` has been permanently frozen via `freezePolicy`.
    ///         Always false for compound and built-in policies.
    function isPolicyFrozen(uint64 policyId) external view returns (bool);

    /// @notice Returns the constituent policy IDs of a compound policy.
    ///
    /// @dev    Reverts with `IncompatiblePolicyType` if the policy is not
    ///         COMPOUND, and with `PolicyNotFound` if the policy does not
    ///         exist.
    function compoundPolicyData(uint64 policyId)
        external
        view
        returns (uint64 senderPolicyId, uint64 recipientPolicyId, uint64 mintRecipientPolicyId, uint64 redeemerPolicyId);
}
