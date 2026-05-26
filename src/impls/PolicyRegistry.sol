// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

/// @title PolicyRegistry
/// @notice Upgradeable Solidity implementation of the `IPolicyRegistry` interface.
///         Manages address-membership policies (allowlists and blocklists) used
///         by B-20 tokens for transfer, mint, and redeem authorization.
///
/// @dev    Upgrades are gated to the contract owner via UUPS. Storage follows
///         ERC-7201 namespaced layout (`base.policy_registry`) to prevent
///         collisions with OZ's own namespaced slots. Policy logic is
///         spec-correspondent with the production Rust precompile.
///
///         Packed policy slot layout (`_layout().policies[id]`):
///         [255]      exists flag — set on create, never cleared.
///         [254:160]  unused.
///         [159:0]    admin address; zero after `renounceAdmin`.
///
///         `PolicyType` is NOT stored — it is recovered from the top byte of `policyId`.
///
/// @author Coinbase (https://github.com/base/base-std)
contract PolicyRegistry is IPolicyRegistry, Ownable2StepUpgradeable, UUPSUpgradeable {
    // ============================================================
    //                         STORAGE LAYOUT
    // ============================================================

    /// @custom:storage-location erc7201:base.policy_registry
    struct Layout {
        /// @dev Packed admin + exists flag per policy.
        mapping(uint64 policyId => uint256 packed) policies;
        /// @dev ALLOWLIST member: true → authorized. BLOCKLIST member: true → blocked.
        mapping(uint64 policyId => mapping(address account => bool)) members;
        /// @dev Staged pending admin for in-flight two-step admin transfers.
        mapping(uint64 policyId => address pendingAdmin) pendingAdmins;
        /// @dev Global monotonic counter for the low 56 bits of every policy ID.
        uint56 nextCounter;
    }

    // keccak256(abi.encode(uint256(keccak256("base.policy_registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x00503aeb06982fa1fe3151dc68f90b3946c55c449dfd447e49dcaece71ba4a00;

    // ============================================================
    //                         CONSTANTS
    // ============================================================

    /// @notice Built-in policy ID that always authorizes any account.
    /// @dev Encodes as a BLOCKLIST at counter 0 (empty blocklist → allow all).
    uint64 public constant ALWAYS_ALLOW_ID = 0;

    /// @notice Built-in policy ID that always rejects any account.
    /// @dev Encodes as an ALLOWLIST at counter 1 (empty allowlist → block all).
    uint64 public constant ALWAYS_BLOCK_ID = (uint64(uint8(PolicyType.ALLOWLIST)) << 56) | 1;

    /// @dev Number of built-in policies written at initialization.
    ///      Custom policy counters start at this value.
    uint56 internal constant BUILTIN_POLICY_COUNT = 2;

    /// @dev Policy ID encoding: top byte = uint8(PolicyType), low 56 bits = counter.
    uint64 internal constant POLICY_ID_TYPE_SHIFT = 56;

    /// @dev Bit position of the existence flag within a packed policy slot.
    uint256 internal constant EXISTS_BIT = 255;

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
        _layout().pendingAdmins[policyId] = newAdmin;
        emit PolicyAdminStaged(policyId, msg.sender, newAdmin);
    }

    /// @inheritdoc IPolicyRegistry
    function finalizeUpdateAdmin(uint64 policyId) external {
        Layout storage $ = _layout();
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
        Layout storage $ = _layout();
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
        bool member = _layout().members[policyId][account];
        return _typeOf(policyId) == PolicyType.ALLOWLIST ? member : !member;
    }

    // ============================================================
    //                       POLICY QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;
        if (!_isWellFormed(policyId)) return false;
        return _layout().policies[policyId] != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (!_isWellFormed(policyId)) return address(0);
        return _decodeAdmin(_layout().policies[policyId]);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        if (!_isWellFormed(policyId)) return address(0);
        return _layout().pendingAdmins[policyId];
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
        Layout storage $ = _layout();
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
        Layout storage $ = _layout();
        if ($.nextCounter >= BUILTIN_POLICY_COUNT) return;
        uint256 packed = _encode(address(0));
        $.policies[ALWAYS_ALLOW_ID] = packed;
        $.policies[ALWAYS_BLOCK_ID] = packed;
        $.nextCounter = BUILTIN_POLICY_COUNT;
    }

    function _batchSetMembers(uint64 policyId, PolicyType policyType, bool value, address[] calldata accounts)
        internal
    {
        if (accounts.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(MAX_BATCH_SIZE);
        mapping(address => bool) storage members = _layout().members[policyId];
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
        packed = _layout().policies[policyId];
        if (packed == 0) revert PolicyNotFound();
    }

    function _makeId(PolicyType policyType, uint56 counter) internal pure returns (uint64) {
        return (uint64(uint8(policyType)) << POLICY_ID_TYPE_SHIFT) | uint64(counter);
    }

    /// @dev Composes a packed slot value with the exists bit set.
    ///      Pass `address(0)` to encode the post-renounce slot.
    function _encode(address admin) internal pure returns (uint256) {
        return (uint256(1) << EXISTS_BIT) | uint256(uint160(admin));
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

    function _layout() private pure returns (Layout storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
