// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {IPolicyRegistry} from "../interfaces/IPolicyRegistry.sol";

/// @title PolicyDataLayout
/// @notice Internal library for encoding and decoding packed policy storage slots.
///
/// @dev Each policy is stored as a single uint256. The low 8 bits are always the
///      PolicyType discriminator; the remaining bits depend on the type:
///
///        WHITELIST / BLACKLIST:
///          [255:168] unused
///          [167:8]   admin address (160 bits)
///          [7:0]     PolicyType
///
///        COMPOUND:
///          [255:194] redeemerPolicyId      (62 bits)
///          [193:132] mintRecipientPolicyId (62 bits)
///          [131:70]  recipientPolicyId     (62 bits)
///          [69:8]    senderPolicyId        (62 bits)
///          [7:0]     PolicyType = 2
///
///      Child policy IDs are stored as 62 bits rather than 64. This lets the type
///      byte plus all four IDs fit in exactly one 256-bit slot (8 + 4*62 = 256).
///      Policy IDs are uint64 in the interface but packed as 62 bits in compound slots.
///      _policyIdCounter would need to reach 2^62 (~4.6e18) for truncation to occur,
///      which is not practically possible.
///
///      All functions are internal so they are inlined at compile time with no
///      runtime overhead.
library PolicyDataLayout {
    uint256 internal constant TYPE_MASK = 0xFF;
    uint256 internal constant ID_BITS = 62;
    uint256 internal constant ID_MASK = (uint256(1) << ID_BITS) - 1;

    uint256 internal constant SENDER_SHIFT = 8;
    uint256 internal constant RECIP_SHIFT = SENDER_SHIFT + ID_BITS; // 70
    uint256 internal constant MINT_SHIFT = RECIP_SHIFT + ID_BITS; // 132
    uint256 internal constant REDEEM_SHIFT = MINT_SHIFT + ID_BITS; // 194

    function encodeSimple(IPolicyRegistry.PolicyType pt, address adm) internal pure returns (uint256) {
        return uint256(pt) | (uint256(uint160(adm)) << 8);
    }

    function encodeCompound(uint64 sender, uint64 recipient, uint64 mintRecipient, uint64 redeemer)
        internal
        pure
        returns (uint256)
    {
        return uint256(IPolicyRegistry.PolicyType.COMPOUND) | (uint256(sender) << SENDER_SHIFT)
            | (uint256(recipient) << RECIP_SHIFT) | (uint256(mintRecipient) << MINT_SHIFT)
            | (uint256(redeemer) << REDEEM_SHIFT);
    }

    function policyType(uint256 packed) internal pure returns (IPolicyRegistry.PolicyType) {
        return IPolicyRegistry.PolicyType(packed & TYPE_MASK);
    }

    function admin(uint256 packed) internal pure returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(packed >> 8));
    }

    // Extracts the child policy ID at the given shift offset.
    function idAt(uint256 packed, uint256 shift) internal pure returns (uint64) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64((packed >> shift) & ID_MASK);
    }
}
