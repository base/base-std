// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";

/// @title PolicySlot
/// @notice Internal library for encoding and decoding packed policy storage slots.
///
/// @dev Each policy is stored as a single uint256. The low 8 bits are always the
///      PolicyType discriminator; the remaining bits depend on the type:
///
///        WHITELIST / BLACKLIST:
///          [255:169] unused
///          [168]     frozen flag (1 = policy is permanently immutable)
///          [167:8]   admin address (160 bits)
///          [7:0]     PolicyType
///
///        COMPOUND:
///          [255:194] redeemerField      (62 bits = 1 type bit + 61 ID bits)
///          [193:132] mintRecipientField (62 bits)
///          [131:70]  recipientField     (62 bits)
///          [69:8]    senderField        (62 bits)
///          [7:0]     PolicyType = 2
///
///      Each constituent field carries both the constituent policy ID (61 bits)
///      and a single type bit (0 = WHITELIST or built-in, 1 = BLACKLIST) so that
///      `isAuthorized*` evaluation needs at most one SLOAD to read the compound
///      slot plus one SLOAD to read the relevant constituent's member set — the
///      constituent's policy slot does NOT need to be loaded on the hot path.
///      The type bit is meaningless for built-in constituents (IDs 0 and 1)
///      because evaluation short-circuits on ID before consulting type.
///
///      Constituent policy IDs are stored as 61 bits. The contract bounds the
///      policy ID counter to never exceed `ID_MASK` so this truncation is
///      structurally impossible.
///
///      All functions are internal so they are inlined at compile time with no
///      runtime overhead.
library PolicySlot {
    uint256 internal constant TYPE_MASK = 0xFF;

    // Simple-policy layout.
    uint256 internal constant ADMIN_SHIFT = 8;
    uint256 internal constant FROZEN_SHIFT = 168;
    uint256 internal constant FROZEN_BIT = uint256(1) << FROZEN_SHIFT;

    // Compound-policy layout.
    uint256 internal constant ID_BITS = 61;
    uint256 internal constant ID_MASK = (uint256(1) << ID_BITS) - 1;
    uint256 internal constant FIELD_BITS = 62; // 1 type bit + 61 ID bits
    uint256 internal constant FIELD_MASK = (uint256(1) << FIELD_BITS) - 1;
    uint256 internal constant TYPE_BIT_OFFSET = ID_BITS; // type bit sits above the 61-bit ID
    uint256 internal constant TYPE_BIT = uint256(1) << TYPE_BIT_OFFSET;

    uint256 internal constant SENDER_SHIFT = 8;
    uint256 internal constant RECIPIENT_SHIFT = SENDER_SHIFT + FIELD_BITS; // 70
    uint256 internal constant MINT_SHIFT = RECIPIENT_SHIFT + FIELD_BITS; // 132
    uint256 internal constant REDEEM_SHIFT = MINT_SHIFT + FIELD_BITS; // 194

    function encodeSimple(IPolicyRegistry.PolicyType policyType, address policyAdmin) internal pure returns (uint256) {
        return uint256(policyType) | (uint256(uint160(policyAdmin)) << ADMIN_SHIFT);
    }

    /// @dev Packs a constituent (policy ID + type bit) into a single 62-bit field.
    ///      Built-in IDs (0, 1) can be passed with any `constituentType`; the type
    ///      bit is ignored at decode time for built-ins.
    function encodeField(uint64 id, IPolicyRegistry.PolicyType constituentType) internal pure returns (uint256) {
        uint256 typeBit = constituentType == IPolicyRegistry.PolicyType.BLACKLIST ? uint256(1) : uint256(0);
        return uint256(id) | (typeBit << TYPE_BIT_OFFSET);
    }

    /// @dev Composes a full compound-policy slot from four pre-encoded constituent fields.
    function encodeCompound(uint256 senderField, uint256 recipientField, uint256 mintField, uint256 redeemerField)
        internal
        pure
        returns (uint256)
    {
        return uint256(IPolicyRegistry.PolicyType.COMPOUND) | (senderField << SENDER_SHIFT)
            | (recipientField << RECIPIENT_SHIFT) | (mintField << MINT_SHIFT) | (redeemerField << REDEEM_SHIFT);
    }

    function decodeType(uint256 packed) internal pure returns (IPolicyRegistry.PolicyType) {
        return IPolicyRegistry.PolicyType(packed & TYPE_MASK);
    }

    function decodeAdmin(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed >> ADMIN_SHIFT));
    }

    function decodeFrozen(uint256 packed) internal pure returns (bool) {
        return (packed & FROZEN_BIT) != 0;
    }

    /// @dev Extracts the constituent policy ID at the given shift offset.
    ///      Used by view functions that only care about the ID, not the type.
    function decodeId(uint256 packed, uint256 shift) internal pure returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64((packed >> shift) & ID_MASK);
    }

    /// @dev Extracts the constituent policy ID and type bit in one operation.
    ///      Used on the authorization hot path so the constituent's own policy slot
    ///      does not need to be loaded.
    function decodeField(uint256 packed, uint256 shift) internal pure returns (uint64 id, bool isBlacklist) {
        uint256 field = (packed >> shift) & FIELD_MASK;
        // forge-lint: disable-next-line(unsafe-typecast)
        id = uint64(field & ID_MASK);
        isBlacklist = (field & TYPE_BIT) != 0;
    }
}
