// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

contract PolicyRegistryNextPolicyIdTest is PolicyRegistryTest {
    /// @notice Verifies nextPolicyId(ALLOWLIST) returns the correct initial encoded id
    /// @dev Global counter starts at 2. The first ALLOWLIST id is
    ///      `(uint64(uint8(PolicyType.ALLOWLIST)) << 56) | 2`
    ///      i.e. discriminator 0x02 in the top byte, counter value 2 in the low 56 bits.
    function test_nextPolicyId_success_allowlistInitialEncoded() public {
        // unimplemented
    }

    /// @notice Verifies nextPolicyId(BLOCKLIST) returns the correct initial encoded id
    /// @dev Global counter starts at 2. The first BLOCKLIST id is
    ///      `(uint64(uint8(PolicyType.BLOCKLIST)) << 56) | 2`
    ///      i.e. discriminator 0x03 in the top byte, counter value 2 in the low 56 bits.
    function test_nextPolicyId_success_blocklistInitialEncoded() public {
        // unimplemented
    }

    /// @notice Verifies nextPolicyId advances by one per createPolicy call regardless of type
    /// @dev Single global counter: each createPolicy call increments it once.
    ///      The top-byte discriminator reflects the type passed to nextPolicyId;
    ///      the low 56 bits advance monotonically regardless of which type was created.
    ///      policyTypeRaw is bounded to ALLOWLIST (2) or BLOCKLIST (3) via vm.assume.
    function test_nextPolicyId_success_advancesPerCreate(uint8 policyTypeRaw, uint8 count) public {
        // unimplemented
    }

    /// @notice Verifies creating one type advances nextPolicyId for the other type
    /// @dev The global counter is shared: creating an ALLOWLIST policy increments the
    ///      counter that BLOCKLIST uses, and vice versa. nextPolicyId(ALLOWLIST) and
    ///      nextPolicyId(BLOCKLIST) always differ only in their top byte — their low
    ///      56 bits are identical at any given point in time.
    function test_nextPolicyId_success_globalCounterSharedAcrossTypes(uint8 allowCount, uint8 blockCount) public {
        // unimplemented
    }
}
