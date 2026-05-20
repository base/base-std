// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryCreatePolicyTest is PolicyRegistryTest {
    /// @notice Verifies createPolicy reverts when admin is the zero address
    /// @dev Required-field guard; checks ZeroAddress() error
    function test_createPolicy_revert_zeroAdmin(address caller, uint8 policyTypeInt) public {
        _assumeValidCaller(caller);
        vm.assume(policyTypeInt == 2 || policyTypeInt == 3);
        IPolicyRegistry.PolicyType pt = IPolicyRegistry.PolicyType(policyTypeInt);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        vm.prank(caller);
        policyRegistry.createPolicy(address(0), pt);
    }

    /// @notice Verifies createPolicy reverts for any policyType value outside the enum
    /// @dev Fuzz confirms only ALLOWLIST / BLOCKLIST are accepted; checks InvalidPolicyType() error
    function test_createPolicy_revert_invalidPolicyType(address caller, address admin_, uint8 policyTypeInt) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.assume(policyTypeInt != 2 && policyTypeInt != 3);
        vm.assume(policyTypeInt < 4); // stay within valid enum cast range
        IPolicyRegistry.PolicyType invalidType = IPolicyRegistry.PolicyType(policyTypeInt);
        vm.expectRevert(IPolicyRegistry.InvalidPolicyType.selector);
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, invalidType);
    }

    /// @notice Verifies createPolicy assigns a fresh allowlist policy id
    /// @dev Type, admin, and existence all readable post-creation
    function test_createPolicy_success_allowlist(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertTrue(policyRegistry.policyExists(policyId));
        assertEq(uint8(policyRegistry.policyType(policyId)), uint8(IPolicyRegistry.PolicyType.ALLOWLIST));
        assertEq(policyRegistry.policyAdmin(policyId), admin_);
    }

    /// @notice Verifies createPolicy assigns a fresh blocklist policy id
    /// @dev Type, admin, and existence all readable post-creation
    function test_createPolicy_success_blocklist(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.BLOCKLIST);
        assertTrue(policyRegistry.policyExists(policyId));
        assertEq(uint8(policyRegistry.policyType(policyId)), uint8(IPolicyRegistry.PolicyType.BLOCKLIST));
        assertEq(policyRegistry.policyAdmin(policyId), admin_);
    }

    /// @notice Verifies the returned policy id advances nextPolicyId monotonically
    /// @dev Sequential creations produce sequential, non-overlapping ids
    function test_createPolicy_success_advancesNextPolicyId(address caller, address admin_, uint8 typeA, uint8 typeB)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.assume(typeA == 2 || typeA == 3);
        vm.assume(typeB == 2 || typeB == 3);
        IPolicyRegistry.PolicyType ptA = IPolicyRegistry.PolicyType(typeA);
        IPolicyRegistry.PolicyType ptB = IPolicyRegistry.PolicyType(typeB);

        uint64 predictedA = policyRegistry.nextPolicyId(ptA);
        vm.prank(caller);
        uint64 idA = policyRegistry.createPolicy(admin_, ptA);
        assertEq(idA, predictedA);

        uint64 predictedB = policyRegistry.nextPolicyId(ptB);
        vm.prank(caller);
        uint64 idB = policyRegistry.createPolicy(admin_, ptB);
        assertEq(idB, predictedB);

        assertTrue(idA != idB);
        // Low 56 bits advance by exactly 1 between any two consecutive creates.
        uint64 counterMask = (uint64(1) << 56) - 1;
        assertEq((idA & counterMask) + 1, idB & counterMask);
    }

    /// @notice Verifies createPolicy emits PolicyCreated with the correct args
    /// @dev Event integrity: policyId, creator, policyType match the call
    function test_createPolicy_success_emitsPolicyCreated(address caller, address admin_, uint8 policyTypeInt) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.assume(policyTypeInt == 2 || policyTypeInt == 3);
        IPolicyRegistry.PolicyType pt = IPolicyRegistry.PolicyType(policyTypeInt);

        uint64 expectedId = policyRegistry.nextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyCreated(expectedId, caller, pt);
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }

    /// @notice Verifies createPolicy emits PolicyAdminUpdated(previousAdmin = 0) on initial assignment
    /// @dev Initial-admin variant of PolicyAdminUpdated; canonical event test lives in finalizeUpdateAdmin.t.sol
    function test_createPolicy_success_emitsInitialPolicyAdminUpdated(
        address caller,
        address admin_,
        uint8 policyTypeInt
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.assume(policyTypeInt == 2 || policyTypeInt == 3);
        IPolicyRegistry.PolicyType pt = IPolicyRegistry.PolicyType(policyTypeInt);

        uint64 expectedId = policyRegistry.nextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(expectedId, address(0), admin_);
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }
}
