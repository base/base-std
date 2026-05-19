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
///        [255:168] unused
///        [167:8]   admin address (160 bits)
///        [7:0]     PolicyType (ALLOWLIST = 0, BLOCKLIST = 1)
///
///      Existence sentinel: _policies[id] == 0 means the policy was
///      never created. This is safe because createPolicy requires a
///      non-zero admin, so a valid packed value is always non-zero.
///
///      Built-in IDs (0 and type(uint64).max) are never stored in
///      _policies; their behavior is handled via constants.
contract PolicyRegistry is IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint64 private constant ALWAYS_ALLOW_ID = 0;
    uint64 private constant ALWAYS_REJECT_ID = type(uint64).max;

    uint256 private constant TYPE_MASK = 0xFF;
    uint256 private constant ADMIN_SHIFT = 8;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 policyId => uint256 packed) private _policies;

    // ALLOWLIST: member == true means the address is authorized.
    // BLOCKLIST: member == true means the address is blocked.
    mapping(uint64 policyId => mapping(address account => bool)) private _members;

    mapping(uint64 policyId => address pendingAdmin) private _pendingAdmins;

    uint64 private _nextId = 1;

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
        _policies[policyId] = _encode({policyType: _decodeType(packed), admin: msg.sender});
        delete _pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, previousAdmin, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function renounceAdmin(uint64 policyId) external {
        uint256 packed = _requireCustom(policyId);
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _policies[policyId] = _encode({policyType: _decodeType(packed), admin: address(0)});
        if (_pendingAdmins[policyId] != address(0)) delete _pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, msg.sender, address(0));
    }

    /// @inheritdoc IPolicyRegistry
    function updateAllowlist(uint64 policyId, bool allowed, address[] calldata accounts) external {
        uint256 packed = _requireCustom(policyId);
        if (_decodeType(packed) != PolicyType.ALLOWLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _batchSetMembers({policyId: policyId, policyType: PolicyType.ALLOWLIST, value: allowed, accounts: accounts});
    }

    /// @inheritdoc IPolicyRegistry
    function updateBlocklist(uint64 policyId, bool blocked, address[] calldata accounts) external {
        uint256 packed = _requireCustom(policyId);
        if (_decodeType(packed) != PolicyType.BLOCKLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _batchSetMembers({policyId: policyId, policyType: PolicyType.BLOCKLIST, value: blocked, accounts: accounts});
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address account) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_REJECT_ID) return false;
        uint256 packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        bool member = _members[policyId][account];
        return _decodeType(packed) == PolicyType.ALLOWLIST ? member : !member;
    }

    /*//////////////////////////////////////////////////////////////
                           POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function nextPolicyId() external view returns (uint64) {
        return _nextId;
    }

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        return policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_REJECT_ID || _policies[policyId] != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyType(uint64 policyId) external view returns (PolicyType) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_REJECT_ID) return PolicyType.ALLOWLIST;
        uint256 packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        return _decodeType(packed);
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_REJECT_ID) return address(0);
        uint256 packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
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
        newPolicyId = _nextId;
        // Overflow is structurally impossible before heat death: uint64.max is the
        // ALWAYS_REJECT sentinel and is never reached by the monotonic counter.
        unchecked {
            ++_nextId;
        }
        _policies[newPolicyId] = _encode({policyType: policyType, admin: admin});
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, address(0), admin);
    }

    function _batchSetMembers(uint64 policyId, PolicyType policyType, bool value, address[] calldata accounts)
        internal
    {
        mapping(address => bool) storage members = _members[policyId];
        if (policyType == PolicyType.ALLOWLIST) {
            emit AllowlistUpdated(policyId, msg.sender, value, accounts);
            for (uint256 i = 0; i < accounts.length; ++i) {
                members[accounts[i]] = value;
            }
        } else {
            emit BlocklistUpdated(policyId, msg.sender, value, accounts);
            for (uint256 i = 0; i < accounts.length; ++i) {
                members[accounts[i]] = value;
            }
        }
    }

    function _requireCustom(uint64 policyId) internal view returns (uint256 packed) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_REJECT_ID) revert PolicyNotFound();
        packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
    }

    function _encode(PolicyType policyType, address admin) internal pure returns (uint256) {
        return uint256(policyType) | (uint256(uint160(admin)) << ADMIN_SHIFT);
    }

    function _decodeType(uint256 packed) internal pure returns (PolicyType) {
        return PolicyType(packed & TYPE_MASK);
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed >> ADMIN_SHIFT));
    }
}
