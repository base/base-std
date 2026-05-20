// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";

/// @title PolicyRegistry
/// @author Coinbase
/// @notice Reference implementation of IPolicyRegistry.
///
/// @dev Storage layout:
///
///      _policies[id]: packed uint256
///        [255:169] unused
///        [168]     created flag (always 1 for existing policies, never cleared)
///        [167:8]   admin address (160 bits, 0 after renounceAdmin)
///        [7:0]     unused
///
///      Existence sentinel: bit 168 (CREATED_BIT). A renounced policy has
///      admin = address(0), making bits [167:8] zero; CREATED_BIT prevents
///      that from being confused with a never-created slot.
///
///      Policy type is NOT stored in the packed slot. It is encoded in the
///      top byte of the policy ID itself per the IPolicyRegistry encoding
///      scheme, and recovered via _typeFromId() with no storage read.
///
///      Built-in IDs (0 and 1) are never stored in _policies; their
///      behavior is handled via constants.
contract PolicyRegistry is IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint64 private constant ALWAYS_ALLOW_ID = 0;
    uint64 private constant ALWAYS_BLOCK_ID = 1;

    // Policy ID encoding: [63:56] = uint8(PolicyType), [55:0] = global counter.
    uint256 private constant TYPE_SHIFT = 56;

    uint256 private constant CREATED_BIT = uint256(1) << 168;
    uint256 private constant ADMIN_SHIFT = 8;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 policyId => uint256 packed) private _policies;

    // ALLOWLIST: member == true means the address is authorized.
    // BLOCKLIST: member == true means the address is blocked.
    mapping(uint64 policyId => mapping(address account => bool)) private _members;

    mapping(uint64 policyId => address pendingAdmin) private _pendingAdmins;

    // Global monotonic counter for the low 56 bits of custom policy IDs.
    // Starts at 2: IDs 0 and 1 are reserved for the built-ins.
    uint56 private _nextCounter = 2;

    /*//////////////////////////////////////////////////////////////
                           POLICY CREATION
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                         POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function stageUpdateAdmin(uint64 policyId, address newAdmin) external {
        uint256 packed = _requireCustom(policyId);
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _pendingAdmins[policyId] = newAdmin;
        emit PolicyAdminStaged(policyId, msg.sender, newAdmin);
    }

    /// @inheritdoc IPolicyRegistry
    function finalizeUpdateAdmin(uint64 policyId) external {
        uint256 packed = _requireCustom(policyId);
        address pending = _pendingAdmins[policyId];
        if (pending == address(0)) revert NoPendingAdmin();
        if (pending != msg.sender) revert Unauthorized();
        address previousAdmin = _decodeAdmin(packed);
        _policies[policyId] = _encode(msg.sender);
        delete _pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, previousAdmin, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function renounceAdmin(uint64 policyId) external {
        uint256 packed = _requireCustom(policyId);
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _policies[policyId] = _encode(address(0));
        if (_pendingAdmins[policyId] != address(0)) delete _pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, msg.sender, address(0));
    }

    /// @inheritdoc IPolicyRegistry
    function updateAllowlist(uint64 policyId, bool allowed, address[] calldata accounts) external {
        uint256 packed = _requireCustom(policyId);
        if (_typeFromId(policyId) != PolicyType.ALLOWLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _batchSetMembers({policyId: policyId, policyType: PolicyType.ALLOWLIST, value: allowed, accounts: accounts});
    }

    /// @inheritdoc IPolicyRegistry
    function updateBlocklist(uint64 policyId, bool blocked, address[] calldata accounts) external {
        uint256 packed = _requireCustom(policyId);
        if (_typeFromId(policyId) != PolicyType.BLOCKLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _batchSetMembers({policyId: policyId, policyType: PolicyType.BLOCKLIST, value: blocked, accounts: accounts});
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address account) external view returns (bool) {
        // Built-in short-circuits MUST remain before any storage read: built-in IDs
        // have no entry in _policies and must never reach the storage path.
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_BLOCK_ID) return false;
        uint256 packed = _policies[policyId];
        if (packed & CREATED_BIT == 0) revert PolicyNotFound();
        bool member = _members[policyId][account];
        return _typeFromId(policyId) == PolicyType.ALLOWLIST ? member : !member;
    }

    /*//////////////////////////////////////////////////////////////
                           POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function nextPolicyId(PolicyType policyType) external view returns (uint64) {
        return _makeId(policyType, _nextCounter);
    }

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;
        return _policies[policyId] & CREATED_BIT != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyType(uint64 policyId) external view returns (PolicyType) {
        if (policyId == ALWAYS_ALLOW_ID) return PolicyType.ALWAYS_ALLOW;
        if (policyId == ALWAYS_BLOCK_ID) return PolicyType.ALWAYS_BLOCK;
        if (_policies[policyId] & CREATED_BIT == 0) revert PolicyNotFound();
        return _typeFromId(policyId);
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        uint256 packed = _policies[policyId];
        if (packed & CREATED_BIT == 0) revert PolicyNotFound();
        return _decodeAdmin(packed);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        return _pendingAdmins[policyId];
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _create(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (policyType != PolicyType.ALLOWLIST && policyType != PolicyType.BLOCKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        uint56 counter = _nextCounter;
        // No overflow guard: at one policy per 2-second block, exhausting the 56-bit
        // counter space (~7.2e16 IDs) takes ~4.6 billion years.
        unchecked {
            _nextCounter = counter + 1;
        }
        newPolicyId = _makeId(policyType, counter);
        _policies[newPolicyId] = _encode(admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, address(0), admin);
    }

    function _batchSetMembers(uint64 policyId, PolicyType policyType, bool value, address[] calldata accounts)
        internal
    {
        mapping(address => bool) storage members = _members[policyId];
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
        packed = _policies[policyId];
        if (packed & CREATED_BIT == 0) revert PolicyNotFound();
    }

    function _makeId(PolicyType policyType, uint56 counter) internal pure returns (uint64) {
        return (uint64(uint8(policyType)) << TYPE_SHIFT) | uint64(counter);
    }

    function _typeFromId(uint64 policyId) internal pure returns (PolicyType) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return PolicyType(uint8(policyId >> TYPE_SHIFT));
    }

    function _encode(address admin) internal pure returns (uint256) {
        return CREATED_BIT | (uint256(uint160(admin)) << ADMIN_SHIFT);
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed >> ADMIN_SHIFT));
    }
}
