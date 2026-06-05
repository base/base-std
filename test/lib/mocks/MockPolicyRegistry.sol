// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

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

    /// @notice Number of built-in policies the registry initializes on
    ///         first use. The global counter is advanced to this value
    ///         once both sentinels are populated, so custom policies
    ///         start at counter `BUILTIN_POLICY_COUNT`.
    /// @dev    Library `internal constant` so callers (tests + the Rust
    ///         impl validator) can reference it at compile time without
    ///         routing through a runtime getter — important because the
    ///         live Rust precompile does NOT expose this value via its
    ///         dispatch ABI.
    uint56 internal constant BUILTIN_POLICY_COUNT = 2;
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
    /// @dev    Useful as an explicit hard-deny on a slot.
    uint64 public constant ALWAYS_BLOCK_ID = PolicyRegistryConstants.ALWAYS_BLOCK_ID;

    // Policy ID encoding: top byte = uint8(PolicyType), low 56 bits = counter.
    uint64 internal constant POLICY_ID_TYPE_SHIFT = 56;

    /// @notice Per-call membership-batch limit. `createPolicyWithAccounts`,
    ///         `updateAllowlist`, and `updateBlocklist` revert with
    ///         `BatchSizeTooLarge(MAX_BATCH_SIZE)` when `accounts.length`
    ///         exceeds this value. Mirrors the Rust PolicyRegistry
    ///         precompile.
    uint256 internal constant MAX_BATCH_SIZE = 64;

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
        // Match the Rust precompile's check precedence:
        //   validate_create_policy_inputs (zero-admin) → require_account_batch_size →
        //   create_policy_inner → write members
        // Both checks are duplicated downstream (`_create` re-checks zero-admin for
        // direct `createPolicy` callers, `_batchSetMembers` re-checks batch size for
        // `updateAllowlist` / `updateBlocklist` callers). The hoisted entry-point
        // copies ensure we revert before any `_create` mutation on the failing path
        // AND pin the same revert-selector precedence Rust enforces (see Rust test
        // `create_policy_with_accounts_zero_admin_precedes_batch_size_revert`).
        if (admin == address(0)) revert ZeroAddress();
        if (accounts.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(MAX_BATCH_SIZE);
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
        // Use the typed `policyExistsFromPacked` helper rather than a raw
        // `packed != 0` test. Functionally identical given the encoding
        // invariant (exists bit is always set when `_encode` writes the
        // slot), but matches the Rust precompile's `packed.exists()`
        // call and survives any future encoding change that adds bits
        // above the admin lane without setting the exists bit.
        return MockPolicyRegistryStorage.policyExistsFromPacked(MockPolicyRegistryStorage.layout().policies[policyId]);
    }

    /// @inheritdoc IPolicyRegistry
    function policyAdmin(uint64 policyId) external view returns (address) {
        if (!_isWellFormed(policyId)) return address(0);
        // No fast path for built-in IDs needed: lazy init writes them with
        // a zero admin, so the normal storage read returns address(0) for
        // them just like for renounced policies and uncreated IDs.
        //
        // No explicit `exists()` gate either: the Rust impl reads `packed`,
        // checks `exists()`, and returns `None` (→ `address(0)` on the ABI
        // boundary) for non-existent slots. The Solidity encoding invariant
        // makes the gate unobservable — a never-written `policies[id]` slot
        // reads as `packed == 0`, so `_decodeAdmin` recovers `address(0)`
        // with no SLOAD overhead vs. the gated implementation.
        return _decodeAdmin(MockPolicyRegistryStorage.layout().policies[policyId]);
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        // Defense-in-depth short-circuit for built-in IDs. The Rust impl
        // gates pending-admin reads on the ID being non-built-in (see
        // `crates/common/precompiles/src/policy/storage.rs` `pending_policy_admin`),
        // so a corrupted `pendingAdmins[builtin]` slot can never leak a
        // non-zero address through the view. The default-zero storage read
        // below would also return `address(0)` for built-ins in normal
        // operation (they never have a pending admin staged), but the
        // explicit branch removes that assumption from the trust boundary.
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
        // Lazy-init the built-in policies on the first create. `_writeBuiltins`
        // is idempotent, so calls after init are a cheap conditional return.
        _writeBuiltins();
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
        uint56 counter = $.nextCounter;
        // Solidity checked arithmetic panics with Panic(0x11) on uint56 overflow,
        // matching the Rust precompile which reverts with Panic(UnderOverflow) at COUNTER_MASK.
        $.nextCounter = counter + 1;
        newPolicyId = _makeId({policyType: policyType, counter: counter});
        $.policies[newPolicyId] = _encode(admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, address(0), admin);
    }

    /// @dev Writes the two built-in policies into the `policies` mapping and
    ///      advances `nextCounter` past them so custom policies start at
    ///      `PolicyRegistryConstants.BUILTIN_POLICY_COUNT`. Both built-ins are
    ///      written with a renounced (zero) admin, so any later `require_admin`
    ///      check against them rejects with `Unauthorized`.
    ///
    ///      Idempotent: re-entry with `nextCounter >= BUILTIN_POLICY_COUNT` is
    ///      a no-op, so `_create` can call this on every entry. Internal /
    ///      not exposed in the ABI to mirror `PolicyRegistryStorage::write_builtins`
    ///      in the Rust precompile, which is `pub` in-crate but absent from
    ///      the dispatched `PolicyRegistry` trait.
    function _writeBuiltins() internal {
        MockPolicyRegistryStorage.Layout storage $ = MockPolicyRegistryStorage.layout();
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
