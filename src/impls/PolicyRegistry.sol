// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";

/// @title PolicyRegistry
/// @notice Reference implementation of the IPolicyRegistry precompile interface.
///
/// @dev Storage layout
/// -------------------
/// Each policy occupies one 256-bit slot in `_policyData`. The low 8 bits are
/// always the PolicyType discriminator; the remaining bits depend on the type:
///
///   WHITELIST / BLACKLIST:
///     [255:168] unused
///     [167:8]   admin address (160 bits)
///     [7:0]     PolicyType
///
///   COMPOUND:
///     [255:194] redeemerPolicyId      (62 bits)
///     [193:132] mintRecipientPolicyId (62 bits)
///     [131:70]  recipientPolicyId     (62 bits)
///     [69:8]    senderPolicyId        (62 bits)
///     [7:0]     PolicyType = 2
///
/// Compound constituent IDs are stored as 62 bits rather than 64. This lets the
/// type byte plus all four IDs fit in exactly one 256-bit slot (8 + 4*62 = 256).
/// Policy IDs are uint64 in the interface but packed as 62 bits in compound slots.
/// _policyIdCounter would need to reach 2^62 (~4.6e18) for truncation to occur,
/// which is not practically possible.
///
/// Existence sentinel: `_policyData[id] == 0` means the policy was never created.
/// This is safe because WHITELIST/BLACKLIST require a non-zero admin (so packed
/// is never zero), and COMPOUND always has type byte = 2 (so packed is never zero).
///
/// Authorization cost: at most 2 SLOADs for any policy. For a compound policy,
/// one SLOAD reads the packed slot (yielding all four constituent IDs), and one
/// SLOAD reads the relevant constituent's member set. Compound constituents cannot
/// themselves be COMPOUND (enforced at creation), so evaluation never goes deeper.
contract PolicyRegistry is IPolicyRegistry {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint64 policyId => uint256 packed) private _policyData;

    // WHITELIST: member == true means the address is allowed.
    // BLACKLIST: member == true means the address is restricted.
    mapping(uint64 policyId => mapping(address account => bool)) private _members;

    uint64 private _counter;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint64 private constant ALWAYS_REJECT_ID = 0;
    uint64 private constant ALWAYS_ALLOW_ID = 1;
    uint64 private constant FIRST_CUSTOM_ID = 2;

    uint256 private constant TYPE_MASK = 0xFF;
    uint256 private constant ID_BITS = 62;
    uint256 private constant ID_MASK = (uint256(1) << ID_BITS) - 1;

    uint256 private constant SENDER_SHIFT = 8;
    uint256 private constant RECIP_SHIFT = SENDER_SHIFT + ID_BITS; // 70
    uint256 private constant MINT_SHIFT = RECIP_SHIFT + ID_BITS; // 132
    uint256 private constant REDEEM_SHIFT = MINT_SHIFT + ID_BITS; // 194

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _counter = FIRST_CUSTOM_ID;
    }

    /*//////////////////////////////////////////////////////////////
                           POLICY CREATION
    //////////////////////////////////////////////////////////////*/

    function createPolicy(address admin, PolicyType policyType) external returns (uint64 newPolicyId) {
        if (policyType != PolicyType.WHITELIST && policyType != PolicyType.BLACKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        newPolicyId = _nextPolicyId();
        _policyData[newPolicyId] = _encodeSimple(policyType, admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, msg.sender, admin);
    }

    function createPolicyWithAccounts(address admin, PolicyType policyType, address[] calldata accounts)
        external
        returns (uint64 newPolicyId)
    {
        if (policyType != PolicyType.WHITELIST && policyType != PolicyType.BLACKLIST) revert InvalidPolicyType();
        if (admin == address(0)) revert ZeroAddress();
        newPolicyId = _nextPolicyId();
        _policyData[newPolicyId] = _encodeSimple(policyType, admin);
        emit PolicyCreated(newPolicyId, msg.sender, policyType);
        emit PolicyAdminUpdated(newPolicyId, msg.sender, admin);
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
            _encodeCompound(senderPolicyId, recipientPolicyId, mintRecipientPolicyId, redeemerPolicyId);
        emit CompoundPolicyCreated(
            newPolicyId, msg.sender, senderPolicyId, recipientPolicyId, mintRecipientPolicyId, redeemerPolicyId
        );
    }

    /*//////////////////////////////////////////////////////////////
                         POLICY ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    function setPolicyAdmin(uint64 policyId, address newAdmin) external {
        if (newAdmin == address(0)) revert ZeroAddress();
        uint256 packed = _loadCustom(policyId);
        PolicyType pt = _decodeType(packed);
        if (pt == PolicyType.COMPOUND) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _policyData[policyId] = _encodeSimple(pt, newAdmin);
        emit PolicyAdminUpdated(policyId, msg.sender, newAdmin);
    }

    function modifyPolicyWhitelist(uint64 policyId, address account, bool allowed) external {
        uint256 packed = _loadCustom(policyId);
        if (_decodeType(packed) != PolicyType.WHITELIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _members[policyId][account] = allowed;
        emit WhitelistUpdated(policyId, msg.sender, account, allowed);
    }

    function modifyPolicyBlacklist(uint64 policyId, address account, bool restricted) external {
        uint256 packed = _loadCustom(policyId);
        if (_decodeType(packed) != PolicyType.BLACKLIST) revert IncompatiblePolicyType();
        if (_decodeAdmin(packed) != msg.sender) revert Unauthorized();
        _members[policyId][account] = restricted;
        emit BlacklistUpdated(policyId, msg.sender, account, restricted);
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPolicyRegistry
    function isAuthorized(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, SENDER_SHIFT) && _checkRole(policyId, user, RECIP_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedSender(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, SENDER_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedRecipient(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, RECIP_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedMintRecipient(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, MINT_SHIFT);
    }

    /// @inheritdoc IPolicyRegistry
    function isAuthorizedRedeemer(uint64 policyId, address user) external view returns (bool) {
        return _checkRole(policyId, user, REDEEM_SHIFT);
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
        policyType = _decodeType(packed);
        admin = policyType == PolicyType.COMPOUND ? address(0) : _decodeAdmin(packed);
    }

    function compoundPolicyData(uint64 policyId)
        external
        view
        returns (uint64 senderPolicyId, uint64 recipientPolicyId, uint64 mintRecipientPolicyId, uint64 redeemerPolicyId)
    {
        uint256 packed = _loadCustom(policyId);
        if (_decodeType(packed) != PolicyType.COMPOUND) revert IncompatiblePolicyType();
        // forge-lint: disable-next-line(unsafe-typecast)
        senderPolicyId = uint64((packed >> SENDER_SHIFT) & ID_MASK);
        // forge-lint: disable-next-line(unsafe-typecast)
        recipientPolicyId = uint64((packed >> RECIP_SHIFT) & ID_MASK);
        // forge-lint: disable-next-line(unsafe-typecast)
        mintRecipientPolicyId = uint64((packed >> MINT_SHIFT) & ID_MASK);
        // forge-lint: disable-next-line(unsafe-typecast)
        redeemerPolicyId = uint64((packed >> REDEEM_SHIFT) & ID_MASK);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _nextPolicyId() internal returns (uint64 id) {
        id = _counter++;
    }

    function _exists(uint64 policyId) internal view returns (bool) {
        return policyId < FIRST_CUSTOM_ID || _policyData[policyId] != 0;
    }

    // Loads the packed slot for a custom policy ID, reverting if it does not exist.
    // Built-in IDs (0, 1) are intentionally excluded: they have no mutable state
    // and cannot be administered.
    function _loadCustom(uint64 policyId) internal view returns (uint256 packed) {
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
        if (_decodeType(packed) == PolicyType.COMPOUND) revert PolicyNotSimple();
    }

    function _encodeSimple(PolicyType policyType, address admin) internal pure returns (uint256) {
        return uint256(policyType) | (uint256(uint160(admin)) << 8);
    }

    function _encodeCompound(uint64 sender, uint64 recipient, uint64 mintRecipient, uint64 redeemer)
        internal
        pure
        returns (uint256)
    {
        return uint256(PolicyType.COMPOUND) | (uint256(sender) << SENDER_SHIFT) | (uint256(recipient) << RECIP_SHIFT)
            | (uint256(mintRecipient) << MINT_SHIFT) | (uint256(redeemer) << REDEEM_SHIFT);
    }

    function _decodeType(uint256 packed) internal pure returns (PolicyType) {
        return PolicyType(packed & TYPE_MASK);
    }

    function _decodeAdmin(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed >> 8));
    }

    // Resolves an authorization check for a single role slot. The roleShift selects
    // which 62-bit field to read from a compound policy's packed slot.
    //
    // For a compound policyId:    1 SLOAD (compound slot) + 1 SLOAD (member set) = 2 SLOADs
    // For a simple policyId:      1 SLOAD (member set)                           = 1 SLOAD
    // For a built-in policyId:    0 SLOADs
    function _checkRole(uint64 policyId, address user, uint256 roleShift) internal view returns (bool) {
        if (policyId == ALWAYS_REJECT_ID) return false;
        if (policyId == ALWAYS_ALLOW_ID) return true;

        uint256 packed = _policyData[policyId];
        PolicyType pt = _decodeType(packed);

        uint64 effectiveId = policyId;
        if (pt == PolicyType.COMPOUND) {
            // forge-lint: disable-next-line(unsafe-typecast)
            effectiveId = uint64((packed >> roleShift) & ID_MASK);
            if (effectiveId == ALWAYS_REJECT_ID) return false;
            if (effectiveId == ALWAYS_ALLOW_ID) return true;
            packed = _policyData[effectiveId];
            pt = _decodeType(packed);
        }

        return pt == PolicyType.WHITELIST ? _members[effectiveId][user] : !_members[effectiveId][user];
    }
}
