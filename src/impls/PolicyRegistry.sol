// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";
import {PolicyDataLayout} from "./PolicyDataLayout.sol";

/// @title PolicyRegistry
/// @notice Implementation of the IPolicyRegistry precompile interface.
///
/// @dev Existence sentinel: `_policyData[id] == 0` means the policy was never created.
///      This is safe because WHITELIST/BLACKLIST require a non-zero admin (so packed
///      is never zero), and COMPOUND always has type byte = 2 (so packed is never zero).
///
///      Authorization cost: at most 2 SLOADs for any policy. For a compound policy,
///      one SLOAD reads the packed slot (yielding all four child IDs), and one SLOAD
///      reads the relevant child's member set. Compound children cannot themselves be
///      COMPOUND (enforced at creation), so evaluation never goes deeper.
contract PolicyRegistry is IPolicyRegistry {
    using PolicyDataLayout for uint256;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 policyId => uint256 packed) private _policyData;

    // WHITELIST: member == true means the address is allowed.
    // BLACKLIST: member == true means the address is restricted.
    mapping(uint64 policyId => mapping(address account => bool)) private _members;

    uint64 private _counter = FIRST_CUSTOM_ID;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint64 private constant ALWAYS_REJECT_ID = 0;
    uint64 private constant ALWAYS_ALLOW_ID = 1;
    uint64 private constant FIRST_CUSTOM_ID = 2;

    /*//////////////////////////////////////////////////////////////
                           POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId) {
        newPolicyId = _createSimple(admin, policyType);
    }

    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId)
    {
        newPolicyId = _createSimple(admin, policyType);
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

    function createCompoundPolicy(
        uint64 senderPolicyId,
        uint64 recipientPolicyId,
        uint64 mintRecipientPolicyId,
        uint64 redeemerPolicyId
    ) external returns (uint64 newPolicyId) {
        _requireSimpleConstituent(senderPolicyId);
        _requireSimpleConstituent(recipientPolicyId);
        _requireSimpleConstituent(mintRecipientPolicyId);
        _requireSimpleConstituent(redeemerPolicyId);
        newPolicyId = _nextPolicyId();
        _policyData[newPolicyId] =
            PolicyDataLayout.encodeCompound(senderPolicyId, recipientPolicyId, mintRecipientPolicyId, redeemerPolicyId);
        emit CompoundPolicyCreated(
            newPolicyId, msg.sender, senderPolicyId, recipientPolicyId, mintRecipientPolicyId, redeemerPolicyId
        );
    }

    /*//////////////////////////////////////////////////////////////
                         POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    function setPolicyAdmin(uint64 policyId, address newAdmin) external {
        if (newAdmin == address(0)) revert ZeroAddress();
        uint256 packed = _requireExists(policyId);
        PolicyType pt = packed.policyType();
        if (pt == PolicyType.COMPOUND) revert IncompatiblePolicyType();
        if (packed.admin() != msg.sender) revert Unauthorized();
        _policyData[policyId] = PolicyDataLayout.encodeSimple(pt, newAdmin);
        emit PolicyAdminUpdated(policyId, msg.sender, newAdmin);
    }

    function modifyPolicyWhitelist(uint64 policyId, address account, bool allowed) external {
        uint256 packed = _requireExists(policyId);
        if (packed.policyType() != PolicyType.WHITELIST) revert IncompatiblePolicyType();
        if (packed.admin() != msg.sender) revert Unauthorized();
        _members[policyId][account] = allowed;
        emit WhitelistUpdated(policyId, msg.sender, account, allowed);
    }

    function modifyPolicyBlacklist(uint64 policyId, address account, bool restricted) external {
        uint256 packed = _requireExists(policyId);
        if (packed.policyType() != PolicyType.BLACKLIST) revert IncompatiblePolicyType();
        if (packed.admin() != msg.sender) revert Unauthorized();
        _members[policyId][account] = restricted;
        emit BlacklistUpdated(policyId, msg.sender, account, restricted);
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicyDataLayout.SENDER_SHIFT)
            && _checkRole(policyId, user, PolicyDataLayout.RECIP_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedSender(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicyDataLayout.SENDER_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedRecipient(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicyDataLayout.RECIP_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedMintRecipient(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicyDataLayout.MINT_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedRedeemer(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, PolicyDataLayout.REDEEM_SHIFT);
    }

    /*//////////////////////////////////////////////////////////////
                           POLICY QUERIES
    //////////////////////////////////////////////////////////////*/

    function policyIdCounter() external view returns (uint64) {
        return _counter;
    }

    function policyExists(uint64 policyId) external view returns (bool) {
        return _exists(policyId);
    }

    function policyData(uint64 policyId) external view returns (PolicyType policyType, address admin) {
        if (!_exists(policyId)) revert PolicyNotFound();
        if (policyId < FIRST_CUSTOM_ID) return (PolicyType.WHITELIST, address(0));
        uint256 packed = _policyData[policyId];
        policyType = packed.policyType();
        admin = policyType == PolicyType.COMPOUND ? address(0) : packed.admin();
    }

    function compoundPolicyData(uint64 policyId)
        external
        view
        returns (uint64 senderPolicyId, uint64 recipientPolicyId, uint64 mintRecipientPolicyId, uint64 redeemerPolicyId)
    {
        uint256 packed = _requireExists(policyId);
        if (packed.policyType() != PolicyType.COMPOUND) revert IncompatiblePolicyType();
        senderPolicyId = packed.idAt(PolicyDataLayout.SENDER_SHIFT);
        recipientPolicyId = packed.idAt(PolicyDataLayout.RECIP_SHIFT);
        mintRecipientPolicyId = packed.idAt(PolicyDataLayout.MINT_SHIFT);
        redeemerPolicyId = packed.idAt(PolicyDataLayout.REDEEM_SHIFT);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _nextPolicyId() internal returns (uint64 id) {
        id = _counter++;
    }

    function _createSimple(address admin, PolicyType policyType) internal returns (uint64 newPolicyId) {
        if (policyType != PolicyType.WHITELIST && policyType != PolicyType.BLACKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        newPolicyId = _nextPolicyId();
        _policyData[newPolicyId] = PolicyDataLayout.encodeSimple(policyType, admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, msg.sender, admin);
    }

    function _exists(uint64 policyId) internal view returns (bool) {
        return policyId < FIRST_CUSTOM_ID || _policyData[policyId] != 0;
    }

    // Loads and returns the packed slot for a custom policy ID, reverting if it does
    // not exist. Built-in IDs (0, 1) are excluded: they have no mutable state.
    function _requireExists(uint64 policyId) internal view returns (uint256 packed) {
        if (policyId < FIRST_CUSTOM_ID) revert PolicyNotFound();
        packed = _policyData[policyId];
        if (packed == 0) revert PolicyNotFound();
    }

    // Validates that policyId is a legal compound constituent: must exist and must
    // not itself be COMPOUND. Built-in IDs 0 and 1 are always valid.
    function _requireSimpleConstituent(uint64 policyId) internal view {
        if (policyId < FIRST_CUSTOM_ID) return;
        uint256 packed = _policyData[policyId];
        if (packed == 0) revert PolicyNotFound();
        if (packed.policyType() == PolicyType.COMPOUND) revert PolicyNotSimple();
    }

    // Resolves an authorization check for a single role slot. The shift selects
    // which 62-bit field to read from a compound policy's packed slot.
    //
    // For a compound policyId:    1 SLOAD (compound slot) + 1 SLOAD (member set) = 2 SLOADs
    // For a simple policyId:      1 SLOAD (member set)                           = 1 SLOAD
    // For a built-in policyId:    0 SLOADs
    function _checkRole(uint64 policyId, address user, uint256 shift) internal view returns (bool) {
        if (policyId == ALWAYS_REJECT_ID) return false;
        if (policyId == ALWAYS_ALLOW_ID) return true;

        uint256 packed = _policyData[policyId];
        PolicyType pt = packed.policyType();

        uint64 effectiveId = policyId;
        if (pt == PolicyType.COMPOUND) {
            effectiveId = packed.idAt(shift);
            if (effectiveId == ALWAYS_REJECT_ID) return false;
            if (effectiveId == ALWAYS_ALLOW_ID) return true;
            packed = _policyData[effectiveId];
            pt = packed.policyType();
        }

        return pt == PolicyType.WHITELIST ? _members[effectiveId][user] : !_members[effectiveId][user];
    }
}
