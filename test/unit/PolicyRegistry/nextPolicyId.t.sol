// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryNextPolicyIdTest is PolicyRegistryTest {
    uint64 private constant TYPE_SHIFT = 56;
    uint56 private constant INITIAL_CUSTOM_COUNTER = 2;

    /// @notice Verifies nextPolicyId(ALLOWLIST) returns the correct initial encoded id
    /// @dev Global counter starts at 2. The first ALLOWLIST id is
    ///      `(uint64(uint8(PolicyType.ALLOWLIST)) << 56) | 2`.
    function test_nextPolicyId_success_allowlistInitialEncoded() public view {
        uint64 expected = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << TYPE_SHIFT) | INITIAL_CUSTOM_COUNTER;
        assertEq(policyRegistry.nextPolicyId(IPolicyRegistry.PolicyType.ALLOWLIST), expected);
    }

    /// @notice Verifies nextPolicyId(BLOCKLIST) returns the correct initial encoded id
    /// @dev Global counter starts at 2. The first BLOCKLIST id is
    ///      `(uint64(uint8(PolicyType.BLOCKLIST)) << 56) | 2`.
    function test_nextPolicyId_success_blocklistInitialEncoded() public view {
        uint64 expected = (uint64(uint8(IPolicyRegistry.PolicyType.BLOCKLIST)) << TYPE_SHIFT) | INITIAL_CUSTOM_COUNTER;
        assertEq(policyRegistry.nextPolicyId(IPolicyRegistry.PolicyType.BLOCKLIST), expected);
    }

    /// @notice Verifies nextPolicyId advances by one per createPolicy call regardless of type
    /// @dev Single global counter: each createPolicy call increments it once.
    ///      policyTypeRaw is bounded to ALLOWLIST (2) or BLOCKLIST (3) via vm.assume.
    function test_nextPolicyId_success_advancesPerCreate(uint8 policyTypeRaw, uint8 count) public {
        vm.assume(policyTypeRaw == 2 || policyTypeRaw == 3);
        count = uint8(bound(count, 0, 10));
        IPolicyRegistry.PolicyType pt = IPolicyRegistry.PolicyType(policyTypeRaw);

        for (uint256 i = 0; i < count; ++i) {
            uint64 predicted = policyRegistry.nextPolicyId(pt);
            uint64 assigned = policyRegistry.createPolicy(admin, pt);
            assertEq(assigned, predicted);
        }
    }

    /// @notice Verifies creating one type advances nextPolicyId for the other type
    /// @dev The global counter is shared: nextPolicyId(ALLOWLIST) and nextPolicyId(BLOCKLIST)
    ///      always differ only in their top byte — their low 56 bits are identical.
    function test_nextPolicyId_success_globalCounterSharedAcrossTypes(uint8 allowCount, uint8 blockCount) public {
        allowCount = uint8(bound(allowCount, 0, 5));
        blockCount = uint8(bound(blockCount, 0, 5));

        for (uint256 i = 0; i < allowCount; ++i) {
            policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        }
        for (uint256 i = 0; i < blockCount; ++i) {
            policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        }

        uint64 nextAllow = policyRegistry.nextPolicyId(IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 nextBlock = policyRegistry.nextPolicyId(IPolicyRegistry.PolicyType.BLOCKLIST);

        // Low 56 bits are identical — both types share the same global counter.
        uint64 counterMask = (uint64(1) << 56) - 1;
        assertEq(nextAllow & counterMask, nextBlock & counterMask);

        // Top bytes differ by type discriminator.
        assertEq(uint8(nextAllow >> 56), uint8(IPolicyRegistry.PolicyType.ALLOWLIST));
        assertEq(uint8(nextBlock >> 56), uint8(IPolicyRegistry.PolicyType.BLOCKLIST));
    }
}
