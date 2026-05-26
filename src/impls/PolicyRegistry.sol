// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";
import {PolicyRegistryConstants, PolicyRegistryStorage} from "src/lib/PolicyRegistryStorage.sol";

/// @title PolicyRegistry
/// @notice Upgradeable Solidity implementation of the `IPolicyRegistry` interface.
///         Manages address-membership policies (allowlists and blocklists) used
///         by B-20 tokens for transfer, mint, and redeem authorization.
///
/// @dev    Upgrades are gated to the contract owner via UUPS. Storage uses the
///         ERC-7201 `base.policy_registry` namespace defined in
///         `PolicyRegistryStorage` to prevent collisions with OZ's own namespaced
///         slots. Policy logic is spec-correspondent with the production Rust
///         precompile; see `PolicyRegistryStorage` for the packed slot layout.
///
/// @author Coinbase (https://github.com/base/base-std)
contract PolicyRegistry is IPolicyRegistry, Ownable2StepUpgradeable, UUPSUpgradeable {
    // ============================================================
    //                         CONSTANTS
    // ============================================================

    /// @notice Built-in policy ID that always authorizes any account.
    uint64 public constant ALWAYS_ALLOW_ID = PolicyRegistryConstants.ALWAYS_ALLOW_ID;

    /// @notice Built-in policy ID that always rejects any account.
    uint64 public constant ALWAYS_BLOCK_ID = PolicyRegistryConstants.ALWAYS_BLOCK_ID;

    /// @dev Policy ID encoding: top byte = uint8(PolicyType), low 56 bits = counter.
    uint64 internal constant POLICY_ID_TYPE_SHIFT = 56;

    /// @notice Per-call membership-batch limit. Reverts with `BatchSizeTooLarge`
    ///         when `accounts.length` exceeds this value.
    uint256 internal constant MAX_BATCH_SIZE = 64;

    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============================================================
    //                       INITIALIZER
    // ============================================================

    /// @notice Initializes the registry, setting the contract owner and
    ///         writing the two built-in sentinel policies.
    ///
    /// @param initialOwner The address granted ownership (and upgrade rights).
    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        _writeBuiltins();
    }

    // ============================================================
    //                       POLICY CREATION
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId) {
        newPolicyId = _create(admin, policyType);
    }

    /// @inheritdoc IPolicyRegistry
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId)
    {
        newPolicyId = _create(admin, policyType);
        _batchSetMembers({policyId: newPolicyId, policyType: policyType, value: true, accounts: accounts});
    }

    // ============================================================
    //                     POLICY ADMINISTRATION
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function stageUpdateAdmin(uint64 policyId, address newAdmin) external {
        uint256 packed = _requireCustom(policyId);
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        PolicyRegistryStorage.layout().pendingAdmins[policyId] = newAdmin;
        emit PolicyAdminStaged(policyId, msg.sender, newAdmin);
    }

    /// @inheritdoc IPolicyRegistry
    function finalizeUpdateAdmin(uint64 policyId) external {
        PolicyRegistryStorage.Layout storage $ = PolicyRegistryStorage.layout();
        uint256 packed = $.policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        address pending = $.pendingAdmins[policyId];
        if (pending == address(0)) revert NoPendingAdmin();
        if (pending != msg.sender) revert Unauthorized();
        address previousAdmin = _decodeAdmin(packed);
        $.policies[policyId] = _encode(msg.sender);
        delete $.pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, previousAdmin, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function renounceAdmin(uint64 policyId) external {
        PolicyRegistryStorage.Layout storage $ = PolicyRegistryStorage.layout();
        uint256 packed = $.policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        // Admin lane cleared; exists bit (bit 255) survives so the policy
        // remains observable via `policyExists` and the existence check on
        // subsequent mutating calls still passes (with Unauthorized taking
        // over as the rejection reason).
        $.policies[policyId] = _encode(address(0));
        delete $.pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, msg.sender, address(0));
    }

    /// @inheritdoc IPolicyRegistry
    function updateAllowlist(uint64 policyId, bool allowed, address[] calldata accounts) external {
        uint256 packed = _requireCustom(policyId);
        if (_typeOf(policyId) != PolicyType.ALLOWLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _batchSetMembers({policyId: policyId, policyType: PolicyType.ALLOWLIST, value: allowed, accounts: accounts});
    }

    /// @inheritdoc IPolicyRegistry
    function updateBlocklist(uint64 policyId, bool blocked, address[] calldata accounts) external {
        uint256 packed = _requireCustom(policyId);
        if (_typeOf(policyId) != PolicyType.BLOCKLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _batchSetMembers({policyId: policyId, policyType: PolicyType.BLOCKLIST, value: blocked, accounts: accounts});
    }

    // ============================================================
    //                    AUTHORIZATION QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address account) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_BLOCK_ID) return false;
        if (!_isWellFormed(policyId)) return false;
        bool member = PolicyRegistryStorage.layout().members[policyId][account];
        return _typeOf(policyId) == PolicyType.ALLOWLIST ? member : !member;
    }

    // ============================================================
    //                       POLICY QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;
        if (!_isWellFormed(policyId)) return false;
        return PolicyRegistryStorage.layout().policies[policyId] != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (!_isWellFormed(policyId)) return address(0);
        return _decodeAdmin(PolicyRegistryStorage.layout().policies[policyId]);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        if (!_isWellFormed(policyId)) return address(0);
        return PolicyRegistryStorage.layout().pendingAdmins[policyId];
    }

    // ============================================================
    //                        UUPS UPGRADE
    // ============================================================

    /// @dev Only the owner may authorize an implementation upgrade.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    function _create(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (admin == address(0)) revert ZeroAddress();
        _writeBuiltins();
        PolicyRegistryStorage.Layout storage $ = PolicyRegistryStorage.layout();
        uint56 counter = $.nextCounter;
        // No overflow guard: at one policy per 2-second block, exhausting
        // the 56-bit counter space takes ~4.6 billion years.
        unchecked {
            $.nextCounter = counter + 1;
        }
        newPolicyId = _makeId({policyType: policyType, counter: counter});
        $.policies[newPolicyId] = _encode(admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, address(0), admin);
    }

    /// @dev Writes the two built-in sentinel policies and advances `nextCounter`
    ///      past them. Idempotent: a no-op when `nextCounter >= BUILTIN_POLICY_COUNT`.
    function _writeBuiltins() internal {
        PolicyRegistryStorage.Layout storage $ = PolicyRegistryStorage.layout();
        if ($.nextCounter >= PolicyRegistryConstants.BUILTIN_POLICY_COUNT) return;
        uint256 packed = _encode(address(0));
        $.policies[PolicyRegistryConstants.ALWAYS_ALLOW_ID] = packed;
        $.policies[PolicyRegistryConstants.ALWAYS_BLOCK_ID] = packed;
        $.nextCounter = PolicyRegistryConstants.BUILTIN_POLICY_COUNT;
    }

    function _batchSetMembers(uint64 policyId, PolicyType policyType, bool value, address[] calldata accounts)
        internal
    {
        if (accounts.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(MAX_BATCH_SIZE);
        mapping(address => bool) storage members = PolicyRegistryStorage.layout().members[policyId];
        for (uint256 i = 0; i < accounts.length; ++i) {
            members[accounts[i]] = value;
        }
        if (policyType == PolicyType.ALLOWLIST) {
            emit AllowlistUpdated(policyId, msg.sender, value, accounts);
        } else {
            emit BlocklistUpdated(policyId, msg.sender, value, accounts);
        }
    }

    function _requireCustom(uint64 policyId) internal view returns (uint256 packed) {
        packed = PolicyRegistryStorage.layout().policies[policyId];
        if (packed == 0) revert PolicyNotFound();
    }

    function _makeId(PolicyType policyType, uint56 counter) internal pure returns (uint64) {
        return (uint64(uint8(policyType)) << POLICY_ID_TYPE_SHIFT) | uint64(counter);
    }

    /// @dev Composes a packed slot value with the exists bit set.
    ///      Pass `address(0)` to encode the post-renounce slot.
    function _encode(address admin) internal pure returns (uint256) {
        return (uint256(1) << PolicyRegistryStorage.EXISTS_BIT) | uint256(uint160(admin));
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed));
    }

    /// @dev Recovers the `PolicyType` from a well-formed `policyId`'s top byte.
    ///      Caller MUST ensure `_isWellFormed(policyId)`.
    function _typeOf(uint64 policyId) internal pure returns (PolicyType) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return PolicyType(uint8(policyId >> POLICY_ID_TYPE_SHIFT));
    }

    /// @dev True iff `policyId`'s top byte is within the `PolicyType` enum range.
    function _isWellFormed(uint64 policyId) internal pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(policyId >> POLICY_ID_TYPE_SHIFT) <= uint8(type(PolicyType).max);
    }
}
