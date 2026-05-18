// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {PolicySlot} from "./PolicySlot.sol";

/// @title PolicyRegistry
/// @notice Implementation of the IPolicyRegistry precompile interface.
///
/// @dev Existence sentinel: `_policyData[id] == 0` means the policy was never created.
///      This is safe because WHITELIST/BLACKLIST require a non-zero admin (so packed
///      is never zero), and COMPOUND always has type byte = 2 (so packed is never zero).
///
///      Authorization cost: exactly 2 SLOADs for any custom policy (zero for built-ins).
///      Compound policies pack each constituent's type bit alongside its ID in the
///      compound slot, so a hot-path check reads only (a) the compound slot and
///      (b) the relevant constituent's member set — the constituent's own policy
///      slot does NOT need to be loaded. Compound constituents cannot themselves be
///      COMPOUND (enforced at creation), so evaluation never goes deeper.
contract PolicyRegistry is IPolicyRegistry {
    using PolicySlot for uint256;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 policyId => uint256 packed) private _policyData;

    // WHITELIST: member == true means the address is allowed.
    // BLACKLIST: member == true means the address is restricted.
    mapping(uint64 policyId => mapping(address account => bool)) private _members;

    // Pending admin per policy. Set by beginPolicyAdminTransfer, cleared on
    // accept/cancel/freeze. Kept in its own mapping (rather than packed into the
    // policy slot) so the hot-path read on _policyData stays minimal; admin
    // rotation is a cold path and the extra SLOAD on accept is acceptable.
    mapping(uint64 policyId => address pendingAdmin) private _pendingAdmins;

    uint64 private _counter = FIRST_USER_POLICY_ID;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint64 private constant ALWAYS_REJECT_ID = 0;
    uint64 private constant ALWAYS_ALLOW_ID = 1;
    uint64 private constant FIRST_USER_POLICY_ID = 2;

    /*//////////////////////////////////////////////////////////////
                           POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId) {
        newPolicyId = _createPolicy(admin, policyType);
    }

    /// @inheritdoc IPolicyRegistry
    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId)
    {
        newPolicyId = _createPolicy(admin, policyType);
        bool isWhitelist = policyType == PolicyType.WHITELIST;
        mapping(address => bool) storage members = _members[newPolicyId];
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            members[account] = true;
            if (isWhitelist) {
                emit WhitelistUpdated(newPolicyId, msg.sender, account, true);
            } else {
                emit BlacklistUpdated(newPolicyId, msg.sender, account, true);
            }
        }
    }

    /// @inheritdoc IPolicyRegistry
    function createCompoundPolicy(
        uint64 senderPolicyId,
        uint64 recipientPolicyId,
        uint64 mintRecipientPolicyId,
        uint64 redeemerPolicyId
    ) external returns (uint64 newPolicyId) {
        // Resolve each constituent's type once, at creation, so the hot path can read
        // the constituent's type bit directly from the compound slot.
        PolicyType senderType = _requireConstituent(senderPolicyId);
        PolicyType recipientType = _requireConstituent(recipientPolicyId);
        PolicyType mintRecipientType = _requireConstituent(mintRecipientPolicyId);
        PolicyType redeemerType = _requireConstituent(redeemerPolicyId);
        newPolicyId = _nextPolicyId();
        _policyData[newPolicyId] = PolicySlot.encodeCompound(
            PolicySlot.encodeField(senderPolicyId, senderType),
            PolicySlot.encodeField(recipientPolicyId, recipientType),
            PolicySlot.encodeField(mintRecipientPolicyId, mintRecipientType),
            PolicySlot.encodeField(redeemerPolicyId, redeemerType)
        );
        emit CompoundPolicyCreated(
            newPolicyId, msg.sender, senderPolicyId, recipientPolicyId, mintRecipientPolicyId, redeemerPolicyId
        );
    }

    /*//////////////////////////////////////////////////////////////
                         POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function beginPolicyAdminTransfer(uint64 policyId, address newAdmin) external {
        // Permitting newAdmin == address(0) here is intentional: it lets the current
        // admin cancel a prior nomination via the same entry point. The pending slot
        // is just a nomination; the active admin doesn't change until accept.
        uint256 packed = _requireExists(policyId);
        PolicyType policyType = packed.decodeType();
        if (policyType == PolicyType.COMPOUND) revert IncompatiblePolicyType();
        if (packed.decodeFrozen()) revert PolicyFrozen();
        if (packed.decodeAdmin() != msg.sender) revert Unauthorized();
        _pendingAdmins[policyId] = newAdmin;
        emit PolicyAdminTransferBegun(policyId, msg.sender, newAdmin);
    }

    /// @inheritdoc IPolicyRegistry
    function acceptPolicyAdminTransfer(uint64 policyId) external {
        uint256 packed = _requireExists(policyId);
        PolicyType policyType = packed.decodeType();
        if (policyType == PolicyType.COMPOUND) revert IncompatiblePolicyType();
        if (packed.decodeFrozen()) revert PolicyFrozen();
        address pending = _pendingAdmins[policyId];
        if (pending != msg.sender) revert NotPendingAdmin();
        // Preserve the frozen bit on rotation. Currently unreachable because the
        // freeze check above short-circuits, but coded defensively in case the
        // freeze semantics evolve (e.g. allowing rotation while frozen).
        _policyData[policyId] = PolicySlot.encodeSimple(policyType, msg.sender)
            | (packed.decodeFrozen() ? PolicySlot.FROZEN_BIT : 0);
        delete _pendingAdmins[policyId];
        emit PolicyAdminUpdated(policyId, msg.sender, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function cancelPolicyAdminTransfer(uint64 policyId) external {
        uint256 packed = _requireExists(policyId);
        PolicyType policyType = packed.decodeType();
        if (policyType == PolicyType.COMPOUND) revert IncompatiblePolicyType();
        if (packed.decodeAdmin() != msg.sender) revert Unauthorized();
        address pending = _pendingAdmins[policyId];
        if (pending == address(0)) revert NoTransferPending();
        delete _pendingAdmins[policyId];
        emit PolicyAdminTransferCancelled(policyId, msg.sender, pending);
    }

    /// @inheritdoc IPolicyRegistry
    function freezePolicy(uint64 policyId) external {
        uint256 packed = _requireExists(policyId);
        PolicyType policyType = packed.decodeType();
        if (policyType == PolicyType.COMPOUND) revert IncompatiblePolicyType();
        if (packed.decodeFrozen()) revert PolicyFrozen();
        if (packed.decodeAdmin() != msg.sender) revert Unauthorized();
        _policyData[policyId] = packed | PolicySlot.FROZEN_BIT;
        // Any in-flight nomination is moot once frozen; clear it so the post-freeze
        // state is unambiguous (no zombie pending admin lingering in storage).
        if (_pendingAdmins[policyId] != address(0)) delete _pendingAdmins[policyId];
        emit PolicyFrozenEvent(policyId, msg.sender);
    }

    /// @inheritdoc IPolicyRegistry
    function modifyPolicyWhitelist(uint64 policyId, address account, bool allowed) external {
        uint256 packed = _requireExists(policyId);
        if (packed.decodeType() != PolicyType.WHITELIST) revert IncompatiblePolicyType();
        if (packed.decodeFrozen()) revert PolicyFrozen();
        if (packed.decodeAdmin() != msg.sender) revert Unauthorized();
        _members[policyId][account] = allowed;
        emit WhitelistUpdated(policyId, msg.sender, account, allowed);
    }

    /// @inheritdoc IPolicyRegistry
    function modifyPolicyBlacklist(uint64 policyId, address account, bool restricted) external {
        uint256 packed = _requireExists(policyId);
        if (packed.decodeType() != PolicyType.BLACKLIST) revert IncompatiblePolicyType();
        if (packed.decodeFrozen()) revert PolicyFrozen();
        if (packed.decodeAdmin() != msg.sender) revert Unauthorized();
        _members[policyId][account] = restricted;
        emit BlacklistUpdated(policyId, msg.sender, account, restricted);
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicySlot.SENDER_SHIFT)
            && _checkRole(policyId, user, PolicySlot.RECIPIENT_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedSender(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicySlot.SENDER_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedRecipient(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicySlot.RECIPIENT_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedMintRecipient(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicySlot.MINT_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedRedeemer(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicySlot.REDEEM_SHIFT);
    }

    /*//////////////////////////////////////////////////////////////
                           POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function policyIdCounter() external view returns (uint64) {
        return _counter;
    }

    /// @inheritdoc IPolicyRegistry
    function policyExists(uint64 policyId) external view returns (bool) {
        return _exists(policyId);
    }

    /// @inheritdoc IPolicyRegistry
    function policyData(uint64 policyId) external view returns (PolicyType policyType, address admin) {
        if (!_exists(policyId)) revert PolicyNotFound();
        if (policyId == ALWAYS_REJECT_ID) return (PolicyType.ALWAYS_REJECT, address(0));
        if (policyId == ALWAYS_ALLOW_ID) return (PolicyType.ALWAYS_ALLOW, address(0));
        uint256 packed = _policyData[policyId];
        policyType = packed.decodeType();
        admin = policyType == PolicyType.COMPOUND ? address(0) : packed.decodeAdmin();
    }

    /// @inheritdoc IPolicyRegistry
    function pendingPolicyAdmin(uint64 policyId) external view returns (address) {
        return _pendingAdmins[policyId];
    }

    /// @inheritdoc IPolicyRegistry
    function isPolicyFrozen(uint64 policyId) external view returns (bool) {
        if (policyId < FIRST_USER_POLICY_ID) return false;
        uint256 packed = _policyData[policyId];
        if (packed == 0) return false;
        if (packed.decodeType() == PolicyType.COMPOUND) return false;
        return packed.decodeFrozen();
    }

    /// @inheritdoc IPolicyRegistry
    function compoundPolicyData(uint64 policyId)
        external
        view
        returns (uint64 senderPolicyId, uint64 recipientPolicyId, uint64 mintRecipientPolicyId, uint64 redeemerPolicyId)
    {
        uint256 packed = _requireExists(policyId);
        if (packed.decodeType() != PolicyType.COMPOUND) revert IncompatiblePolicyType();
        senderPolicyId = packed.decodeId(PolicySlot.SENDER_SHIFT);
        recipientPolicyId = packed.decodeId(PolicySlot.RECIPIENT_SHIFT);
        mintRecipientPolicyId = packed.decodeId(PolicySlot.MINT_SHIFT);
        redeemerPolicyId = packed.decodeId(PolicySlot.REDEEM_SHIFT);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _nextPolicyId() internal returns (uint64 id) {
        id = _counter++;
        // The on-chain compound-policy packing reserves 61 bits per constituent ID.
        // Bounding the counter here guarantees that every policy ID ever created can
        // be round-tripped through the compound slot without silent truncation; the
        // packed-field decoders elsewhere in this contract can therefore rely on
        // ID <= PolicySlot.ID_MASK without re-checking.
        if (id > PolicySlot.ID_MASK) revert PolicyIdOverflow();
    }

    function _createPolicy(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (policyType != PolicyType.WHITELIST && policyType != PolicyType.BLACKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        newPolicyId = _nextPolicyId();
        _policyData[newPolicyId] = PolicySlot.encodeSimple(policyType, admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, msg.sender, admin);
    }

    function _exists(uint64 policyId) internal view returns (bool) {
        return policyId < FIRST_USER_POLICY_ID || _policyData[policyId] != 0;
    }

    // Loads and returns the packed slot for a custom policy ID, reverting if it does
    // not exist. Built-in IDs (0, 1) are excluded: they have no mutable state.
    function _requireExists(uint64 policyId) internal view returns (uint256 packed) {
        if (policyId < FIRST_USER_POLICY_ID) revert PolicyNotFound();
        packed = _policyData[policyId];
        if (packed == 0) revert PolicyNotFound();
    }

    // Validates that policyId is a legal compound constituent and returns its type.
    // Must exist and must be WHITELIST or BLACKLIST. Built-in IDs (0, 1) are always
    // valid; their returned type is WHITELIST as a placeholder (the type bit is
    // ignored on the hot path for built-ins because evaluation short-circuits on ID).
    function _requireConstituent(uint64 policyId) internal view returns (PolicyType) {
        if (policyId < FIRST_USER_POLICY_ID) return PolicyType.WHITELIST;
        uint256 packed = _policyData[policyId];
        if (packed == 0) revert PolicyNotFound();
        PolicyType policyType = packed.decodeType();
        if (policyType != PolicyType.WHITELIST && policyType != PolicyType.BLACKLIST) revert ConstituentIsCompound();
        return policyType;
    }

    // Resolves an authorization check for a single role slot. The shift selects
    // which 62-bit constituent field to read from a compound policy's packed slot.
    //
    // For a compound policyId:    1 SLOAD (compound slot) + 1 SLOAD (member set) = 2 SLOADs
    // For a simple policyId:      1 SLOAD (policy slot)   + 1 SLOAD (member set) = 2 SLOADs
    // For a built-in policyId:    0 SLOADs
    function _checkRole(uint64 policyId, address user, uint256 shift) internal view returns (bool) {
        if (policyId == ALWAYS_REJECT_ID) return false;
        if (policyId == ALWAYS_ALLOW_ID) return true;

        uint256 packed = _policyData[policyId];
        PolicyType policyType = packed.decodeType();

        if (policyType == PolicyType.COMPOUND) {
            (uint64 constituentId, bool isBlacklist) = packed.decodeField(shift);
            if (constituentId == ALWAYS_REJECT_ID) return false;
            if (constituentId == ALWAYS_ALLOW_ID) return true;
            bool member = _members[constituentId][user];
            return isBlacklist ? !member : member;
        }

        bool simpleMember = _members[policyId][user];
        return policyType == PolicyType.WHITELIST ? simpleMember : !simpleMember;
    }
}
