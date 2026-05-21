// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {MockPolicyRegistryStorage} from "test/lib/mocks/MockPolicyRegistryStorage.sol";

/// @notice Canonical built-in policy ID constants. Declared as a library
///         so tests can reference them at compile time via
///         `PolicyRegistryConstants.ALWAYS_ALLOW_ID` — Solidity's
///         `public constant` on a contract is only accessible via instance
///         call, which doesn't work for compile-time constant contexts.
/// @dev    `MockPolicyRegistry` re-exposes each value as `uint64 public
///         constant` to satisfy the runtime-getter contract; this library
///         is the single source of truth.
library PolicyRegistryConstants {
    /// @notice Built-in policy ID that always authorizes any account.
    uint64 internal constant ALWAYS_ALLOW_ID = 0;

    /// @notice Built-in policy ID that always rejects any account.
    uint64 internal constant ALWAYS_BLOCK_ID = 1;
}

/// @title MockPolicyRegistry
/// @notice Reference implementation of the `IPolicyRegistry` precompile.
///         Etched at the canonical policy-registry address via `vm.etch`
///         from `BaseTest.setUp`.
///
/// @dev    Written as Solidity-as-if-Rust: unambiguous spec-correspondence
///         with the production Rust precompile is the goal, not gas
///         optimisation or Solidity idiom adherence.
///
///         All mutable state lives in `MockPolicyRegistryStorage.layout()` at
///         a single ERC-7201-namespaced root. The struct field order IS the
///         slot layout the Rust impl mirrors. See `MockPolicyRegistryStorage`
///         for the full layout documentation and per-field slot offsets.
///
///         This implementation uses two independent encodings:
///         1) `policyId` (uint64) packs type + counter only.
///         2) `policies[policyId]` (uint256) packs policyType + mutable admin.
///
///         **Policy ID encoding (`policyId`):**
///           [63:56]  uint8(PolicyType) discriminator
///           [55:0]   nextCounter value at creation time
///         `_create` rejects ALWAYS_ALLOW and ALWAYS_BLOCK types, so no
///         custom ID ever carries discriminator 0x00 or 0x01.
///
///         **Built-in IDs** (short-circuited before any storage read):
///           0 — ALWAYS_ALLOW: isAuthorized always returns true.
///           1 — ALWAYS_BLOCK: isAuthorized always returns false.
contract MockPolicyRegistry is IPolicyRegistry {
    // ============================================================
    //                         CONSTANTS
    // ============================================================

    /// @notice Built-in policy ID that always authorizes any account.
    /// @dev    The default value for an unconfigured policy slot.
    uint64 public constant ALWAYS_ALLOW_ID = PolicyRegistryConstants.ALWAYS_ALLOW_ID;

    /// @notice Built-in policy ID that always rejects any account.
    /// @dev    Useful as an explicit hard-deny on a slot (e.g. disabling
    ///         redemption by pointing `REDEEM_SENDER_POLICY` here).
    uint64 public constant ALWAYS_BLOCK_ID = PolicyRegistryConstants.ALWAYS_BLOCK_ID;

    /// @notice First counter value handed out to custom policies. Floors
    ///         `nextCounter` so the low 56 bits of the first custom ID can
    ///         never collide with the built-in IDs 0 / 1.
    uint56 internal constant INITIAL_CUSTOM_COUNTER = 2;

    // Policy ID encoding: top byte = uint8(PolicyType), low 56 bits = counter.
    uint64 internal constant POLICY_ID_TYPE_SHIFT = 56;

    // Packed policy slot encoding (`policies[policyId]`):
    // admin address occupies bits [167:8]; PolicyType occupies bits [7:0].
    uint256 internal constant PACKED_ADMIN_SHIFT = 8;

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
        MockPolicyRegistryStorage.layout().pendingAdmins[policyId] = newAdmin;
        emit PolicyAdminStaged(policyId, msg.sender, newAdmin);
    }

    /// @inheritdoc IPolicyRegistry
    function finalizeUpdateAdmin(uint64 policyId) external {
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint256 packed = $.policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        address pending = $.pendingAdmins[policyId];
        if (pending == address(0)) revert NoPendingAdmin();
        if (pending != msg.sender) revert Unauthorized();
        address previousAdmin = _decodeAdmin(packed);
        $.policies[policyId] = _encode({policyType: _decodeType(packed), admin: msg.sender});
        delete $.pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, previousAdmin, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function renounceAdmin(uint64 policyId) external {
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint256 packed = $.policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        $.policies[policyId] = _encode({policyType: _decodeType(packed), admin: address(0)});
        delete $.pendingAdmins[policyId];
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
        _requireWellFormed(policyId);
        // Built-in short-circuits MUST precede any storage read: IDs 0 and 1
        // have no entry in storage and must never reach the storage path.
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_BLOCK_ID) return false;
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint256 packed = $.policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        bool member = $.members[policyId][account];
        return _decodeType(packed) == PolicyType.ALLOWLIST ? member : !member;
    }

    // ============================================================
    //                       POLICY QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function nextPolicyId(PolicyType policyType) external view returns (uint64) {
        uint56 counter = MockPolicyRegistryStorage.layout().nextCounter;
        if (counter < INITIAL_CUSTOM_COUNTER) counter = INITIAL_CUSTOM_COUNTER;
        return _makeId({policyType: policyType, counter: counter});
    }

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        _requireWellFormed(policyId);
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;
        return MockPolicyRegistryStorage.layout().policies[policyId] != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyType(uint64 policyId) external view returns (PolicyType) {
        _requireWellFormed(policyId);
        if (policyId == ALWAYS_ALLOW_ID) return PolicyType.ALWAYS_ALLOW;
        if (policyId == ALWAYS_BLOCK_ID) return PolicyType.ALWAYS_BLOCK;
        uint256 packed = MockPolicyRegistryStorage.layout().policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        return _decodeType(packed);
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        _requireWellFormed(policyId);
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        uint256 packed = MockPolicyRegistryStorage.layout().policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        return _decodeAdmin(packed);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        _requireWellFormed(policyId);
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        return MockPolicyRegistryStorage.layout().pendingAdmins[policyId];
    }

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    function _create(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (policyType != PolicyType.ALLOWLIST && policyType != PolicyType.BLOCKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint56 counter = $.nextCounter;
        if (counter < INITIAL_CUSTOM_COUNTER) counter = INITIAL_CUSTOM_COUNTER;
        // No overflow guard: at one policy per 2-second block, exhausting the
        // 56-bit counter space (~7.2e16 values) takes ~4.6 billion years.
        unchecked {
            $.nextCounter = counter + 1;
        }
        newPolicyId = _makeId({policyType: policyType, counter: counter});
        $.policies[newPolicyId] = _encode({policyType: policyType, admin: admin});
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, address(0), admin);
    }

    function _batchSetMembers(uint64 policyId, PolicyType policyType, bool value, address[] calldata accounts)
        internal
    {
        mapping(address => bool) storage members = MockPolicyRegistryStorage.layout().members[policyId];
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
        packed = MockPolicyRegistryStorage.layout().policies[policyId];
        if (packed == 0) revert PolicyNotFound();
    }

    function _makeId(PolicyType policyType, uint56 counter) internal pure returns (uint64) {
        return (uint64(uint8(policyType)) << POLICY_ID_TYPE_SHIFT) | uint64(counter);
    }

    function _encode(PolicyType policyType, address admin) internal pure returns (uint256) {
        return (uint256(uint160(admin)) << PACKED_ADMIN_SHIFT) | uint256(policyType);
    }

    function _decodeType(uint256 packed) internal pure returns (PolicyType) {
        return PolicyType(uint8(packed));
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        return address(uint160(packed >> PACKED_ADMIN_SHIFT));
    }

    /// @dev Reverts `MalformedPolicyId` if `policyId`'s top byte (the
    ///      `PolicyType` discriminator) is outside the enum range. Every
    ///      entry point that accepts a `policyId` calls this first, so
    ///      malformed IDs are rejected distinctly from well-formed
    ///      IDs that simply haven't been created (which still revert
    ///      `PolicyNotFound`).
    function _requireWellFormed(uint64 policyId) internal pure {
        if (uint8(policyId >> POLICY_ID_TYPE_SHIFT) > uint8(type(PolicyType).max)) {
            revert MalformedPolicyId(policyId);
        }
    }
}
