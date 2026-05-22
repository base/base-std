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
    /// @dev    Encodes as a BLOCKLIST at counter 0 (empty blocklist → allow all).
    uint64 internal constant ALWAYS_ALLOW_ID = 0;

    /// @notice Built-in policy ID that always rejects any account.
    /// @dev    Encodes as an ALLOWLIST at counter 1 (empty allowlist → block all).
    uint64 internal constant ALWAYS_BLOCK_ID = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | 1;
}

/// @title MockPolicyRegistry
/// @notice Reference implementation of the `IPolicyRegistry` precompile.
///         Etched at the canonical policy-registry address via `vm.etch`
///         from `BaseTest.setUp`.
///
/// @dev    Solidity-as-if-Rust: spec-correspondence with the production
///         Rust precompile, not gas-optimal Solidity. All mutable state
///         lives in `MockPolicyRegistryStorage.layout()` at a single
///         ERC-7201-namespaced root; see that library for the layout.
///
///         Policy ID encoding: top byte = `uint8(PolicyType)`; low 56
///         bits = counter. Type is recoverable from the ID alone (no
///         SLOAD), so the packed storage slot stores only admin + an
///         exists flag, not the type.
///
///         Built-in IDs (short-circuited in `isAuthorized` before any
///         SLOAD): `ALWAYS_ALLOW_ID` (empty BLOCKLIST → allow all) and
///         `ALWAYS_BLOCK_ID` (empty ALLOWLIST → block all). The values
///         are chosen so the encoding reads as the natural degenerate
///         form of each list type.
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

    /// @notice First counter value handed out to custom policies. Skips
    ///         counters `0` (ALWAYS_ALLOW) and `1` (ALWAYS_BLOCK).
    uint56 internal constant INITIAL_CUSTOM_COUNTER = 2;

    // Policy ID encoding: top byte = uint8(PolicyType), low 56 bits = counter.
    uint64 internal constant POLICY_ID_TYPE_SHIFT = 56;

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
        $.policies[policyId] = _encode(msg.sender);
        delete $.pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, previousAdmin, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function renounceAdmin(uint64 policyId) external {
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint256 packed = $.policies[policyId];
        if (packed == 0) revert PolicyNotFound();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        // Admin lane cleared, exists flag (bit 160) survives so the
        // policy stays observable via `policyExists` and the existence
        // check on subsequent mutating calls still passes (with
        // `Unauthorized` taking over as the rejection reason).
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
        // Built-in short-circuits precede any SLOAD; sentinels have no
        // storage entry.
        if (policyId == ALWAYS_ALLOW_ID) return true;
        if (policyId == ALWAYS_BLOCK_ID) return false;
        // Short-circuit malformed IDs so the `_typeOf` enum cast can't panic.
        if (!_isWellFormed(policyId)) return false;
        // Hot path: one SLOAD (the membership bit). No existence check —
        // callers pre-validate via `policyExists` at write time. For
        // non-existent IDs the result collapses to empty-member-set
        // semantics (ALLOWLIST → false, BLOCKLIST → true).
        bool member = MockPolicyRegistryStorage.layout().members[policyId][account];
        return _typeOf(policyId) == PolicyType.ALLOWLIST ? member : !member;
    }

    // ============================================================
    //                       POLICY QUERIES
    // ============================================================

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return true;
        if (!_isWellFormed(policyId)) return false;
        return MockPolicyRegistryStorage.layout().policies[policyId] != 0;
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        if (!_isWellFormed(policyId)) return address(0);
        // Returns address(0) for both "never created" and "renounced".
        return _decodeAdmin(MockPolicyRegistryStorage.layout().policies[policyId]);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        if (policyId == ALWAYS_ALLOW_ID || policyId == ALWAYS_BLOCK_ID) return address(0);
        if (!_isWellFormed(policyId)) return address(0);
        return MockPolicyRegistryStorage.layout().pendingAdmins[policyId];
    }

    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================

    function _create(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (admin == address(0)) revert ZeroAddress();
        // Out-of-range `policyType` rejected by ABI decoding before this body runs.
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint56 counter = $.nextCounter;
        if (counter < INITIAL_CUSTOM_COUNTER) counter = INITIAL_CUSTOM_COUNTER;
        // No overflow guard: at one policy per 2-second block, exhausting the
        // 56-bit counter space (~7.2e16 values) takes ~4.6 billion years.
        unchecked {
            $.nextCounter = counter + 1;
        }
        newPolicyId = _makeId({policyType: policyType, counter: counter});
        $.policies[newPolicyId] = _encode(admin);
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

    /// @dev Composes a packed slot value. Always sets the exists bit; pass
    ///      `address(0)` to encode the post-renounce slot.
    function _encode(address admin) internal pure returns (uint256) {
        return (uint256(1) << MockPolicyRegistryStorage.EXISTS_BIT) | uint256(uint160(admin));
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        return address(uint160(packed));
    }

    /// @dev Recovers the `PolicyType` from a well-formed `policyId`'s top byte.
    ///      Caller MUST ensure `_isWellFormed(policyId)`; otherwise the cast panics.
    function _typeOf(uint64 policyId) internal pure returns (PolicyType) {
        return PolicyType(uint8(policyId >> POLICY_ID_TYPE_SHIFT));
    }

    /// @dev True iff `policyId`'s top byte is within the `PolicyType` enum range.
    function _isWellFormed(uint64 policyId) internal pure returns (bool) {
        return uint8(policyId >> POLICY_ID_TYPE_SHIFT) <= uint8(type(PolicyType).max);
    }
}
