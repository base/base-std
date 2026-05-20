// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

/// @title MockPolicyRegistry
/// @notice Reference implementation of the `IPolicyRegistry` precompile.
///         Etched at the canonical policy-registry address via `vm.etch`
///         from `BaseTest.setUp`.
///
/// @dev    Written as Solidity-as-if-Rust: unambiguous spec-correspondence
///         with the production Rust precompile is the goal, not gas
///         optimisation or Solidity idiom adherence.
///
///         **Storage layout** (Rust impl mirrors these fields in order):
///
///         `_policies[id]` — packed uint256:
///           [255:168]  unused
///           [167:8]    admin address (160 bits). Zero after renounceAdmin.
///           [7:0]      PolicyType (ALLOWLIST = 2, BLOCKLIST = 3).
///                      Since both values are non-zero, `packed == 0`
///                      reliably means the policy was never created, even
///                      after renounceAdmin zeroes the admin field. No
///                      separate existence sentinel is required.
///
///         `_members[policyId][account]` — bool:
///           ALLOWLIST: true → account IS authorized.
///           BLOCKLIST: true → account IS blocked (NOT authorized).
///
///         `_pendingAdmins[policyId]` — address staged by stageUpdateAdmin.
///
///         `_nextCounter` — uint56 global counter for the low 56 bits of
///           custom policy IDs. Starts at 0. The discriminator byte in bits
///           [63:56] ensures no custom ID can equal built-in 0 or 1
///           (ALLOWLIST = 0x02, BLOCKLIST = 0x03, minimum custom ID is
///           0x0200000000000000).
///
///         **Policy ID encoding:**
///           [63:56]  uint8(PolicyType) discriminator
///           [55:0]   _nextCounter value at creation time
///         _create rejects ALWAYS_ALLOW and ALWAYS_BLOCK types, so no
///         custom ID ever carries discriminator 0x00 or 0x01.
///
///         **Built-in IDs** (short-circuited before any storage read):
///           0 — ALWAYS_ALLOW: isAuthorized always returns true.
///           1 — ALWAYS_BLOCK: isAuthorized always returns false.
contract MockPolicyRegistry is IPolicyRegistry {
    // ============================================================
    //                         CONSTANTS
    // ============================================================

    uint64 internal constant ALWAYS_ALLOW_ID = 0;
    uint64 internal constant ALWAYS_BLOCK_ID = 1;

    // Policy ID encoding: top byte = uint8(PolicyType), low 56 bits = counter.
    uint256 internal constant TYPE_SHIFT = 56;

    // Admin address occupies bits [167:8]; PolicyType occupies bits [7:0].
    uint256 internal constant ADMIN_SHIFT = 8;

    // ============================================================
    //                          STORAGE
    // ============================================================

    mapping(uint64 policyId => uint256 packed) private _policies;
    mapping(uint64 policyId => mapping(address account => bool)) private _members;
    mapping(uint64 policyId => address pendingAdmin) private _pendingAdmins;

    // Global monotonic counter for the low 56 bits of custom policy IDs.
    // Starts at 0. The discriminator byte in bits [63:56] ensures no custom ID
    // can equal built-in 0 or 1 regardless of counter value.
    uint56 private _nextCounter;

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
        delete _pendingAdmins[policyId];
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

    // ============================================================
    //                    AUTHORIZATION QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address account) external view returns (bool) {
        // Built-in short-circuits MUST precede any storage read: IDs 0 and 1
        // have no entry in _policies and must never reach the storage path.
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_BLOCK_ID) return false;
        uint256 packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        bool member = _members[policyId][account];
        return _decodeType(packed) == PolicyType.ALLOWLIST ? member : !member;
    }

    // ============================================================
    //                       POLICY QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function nextPolicyId(PolicyType policyType) external view returns (uint64) {
        return _makeId({policyType: policyType, counter: _nextCounter});
    }

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;
        return _policies[policyId] != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyType(uint64 policyId) external view returns (PolicyType) {
        if (policyId == ALWAYS_ALLOW_ID) return PolicyType.ALWAYS_ALLOW;
        if (policyId == ALWAYS_BLOCK_ID) return PolicyType.ALWAYS_BLOCK;
        uint256 packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        return _decodeType(packed);
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        uint256 packed = _policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        return _decodeAdmin(packed);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        return _pendingAdmins[policyId];
    }

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    function _create(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (policyType != PolicyType.ALLOWLIST && policyType != PolicyType.BLOCKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        uint56 counter = _nextCounter;
        // No overflow guard: at one policy per 2-second block, exhausting the
        // 56-bit counter space (~7.2e16 values) takes ~4.6 billion years.
        unchecked {
            _nextCounter = counter + 1;
        }
        newPolicyId = _makeId({policyType: policyType, counter: counter});
        _policies[newPolicyId] = _encode({policyType: policyType, admin: admin});
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
        if (packed == 0) revert PolicyNotFound();
    }

    function _makeId(PolicyType policyType, uint56 counter) internal pure returns (uint64) {
        return (uint64(uint8(policyType)) << TYPE_SHIFT) | uint64(counter);
    }

    function _encode(PolicyType policyType, address admin) internal pure returns (uint256) {
        return (uint256(uint160(admin)) << ADMIN_SHIFT) | uint256(policyType);
    }

    function _decodeType(uint256 packed) internal pure returns (PolicyType) {
        return PolicyType(uint8(packed));
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        return address(uint160(packed >> ADMIN_SHIFT));
    }
}
