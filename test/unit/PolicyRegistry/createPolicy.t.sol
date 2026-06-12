// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {MockPolicyRegistryStorage} from "base-std-test/lib/mocks/MockPolicyRegistryStorage.sol";

contract PolicyRegistryCreatePolicyTest is PolicyRegistryTest {
    /// @notice Verifies createPolicy reverts when admin is the zero address
    /// @dev Required-field guard; checks ZeroAddress() error
    function test_createPolicy_revert_zeroAdmin(address caller, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);
        vm.expectRevert(IPolicyRegistry.ZeroAddress.selector);
        vm.prank(caller);
        policyRegistry.createPolicy(address(0), pt);
    }

    /// @notice Verifies createPolicy assigns a fresh allowlist policy id
    /// @dev Paired slot: admin lane matches, exists bit set, ID top byte = ALLOWLIST.
    function test_createPolicy_success_allowlist(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertTrue(policyRegistry.policyExists(policyId));
        assertEq(policyRegistry.policyAdmin(policyId), admin_);

        uint256 packed = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)));
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(packed),
            admin_,
            "policies[id] slot admin must reflect createPolicy admin"
        );
        assertTrue(MockPolicyRegistryStorage.policyExistsFromPacked(packed), "policies[id] slot exists bit must be set");
        assertEq(
            MockPolicyRegistryStorage.policyTypeFromId(policyId),
            uint8(IPolicyRegistry.PolicyType.ALLOWLIST),
            "policy ID high byte must encode ALLOWLIST"
        );
    }

    /// @notice Verifies createPolicy assigns a fresh blocklist policy id
    /// @dev Paired slot: admin lane matches, exists bit set, ID top byte = BLOCKLIST.
    function test_createPolicy_success_blocklist(address caller, address admin_) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        vm.prank(caller);
        uint64 policyId = policyRegistry.createPolicy(admin_, IPolicyRegistry.PolicyType.BLOCKLIST);
        assertTrue(policyRegistry.policyExists(policyId));
        assertEq(policyRegistry.policyAdmin(policyId), admin_);

        uint256 packed = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.policySlot(policyId)));
        assertEq(
            MockPolicyRegistryStorage.policyAdminFromPacked(packed),
            admin_,
            "policies[id] slot admin must reflect createPolicy admin"
        );
        assertTrue(MockPolicyRegistryStorage.policyExistsFromPacked(packed), "policies[id] slot exists bit must be set");
        assertEq(
            MockPolicyRegistryStorage.policyTypeFromId(policyId),
            uint8(IPolicyRegistry.PolicyType.BLOCKLIST),
            "policy ID high byte must encode BLOCKLIST"
        );
    }

    /// @notice Verifies sequential creates advance the global counter by exactly 1.
    /// @dev    Paired slot: `nextCounter` lands at `(idB & mask) + 1` after both creates.
    function test_createPolicy_success_advancesNextPolicyId(
        address caller,
        address admin_,
        uint8 typeIdxA,
        uint8 typeIdxB
    ) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType ptA = _creatablePolicyType(typeIdxA);
        IPolicyRegistry.PolicyType ptB = _creatablePolicyType(typeIdxB);

        uint64 predictedA = _predictNextPolicyId(ptA);
        vm.prank(caller);
        uint64 idA = policyRegistry.createPolicy(admin_, ptA);
        assertEq(idA, predictedA);

        uint64 predictedB = _predictNextPolicyId(ptB);
        vm.prank(caller);
        uint64 idB = policyRegistry.createPolicy(admin_, ptB);
        assertEq(idB, predictedB);

        assertTrue(idA != idB);
        uint64 counterMask = (uint64(1) << 56) - 1;
        assertEq((idA & counterMask) + 1, idB & counterMask);

        uint256 counterAfter = uint256(vm.load(address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot()));
        assertEq(
            counterAfter, uint256(idB & counterMask) + 1, "nextCounter slot must equal the second policy's counter + 1"
        );
    }

    /// @notice Verifies createPolicy emits PolicyCreated with the correct args
    function test_createPolicy_success_emitsPolicyCreated(address caller, address admin_, uint8 typeIdx) public {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);

        uint64 expectedId = _predictNextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyCreated(expectedId, caller, pt);
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }

    /// @notice Verifies createPolicy emits PolicyAdminUpdated(previousAdmin = 0) on initial assignment
    function test_createPolicy_success_emitsInitialPolicyAdminUpdated(address caller, address admin_, uint8 typeIdx)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);

        uint64 expectedId = _predictNextPolicyId(pt);
        vm.expectEmit(address(policyRegistry));
        emit IPolicyRegistry.PolicyAdminUpdated(expectedId, address(0), admin_);
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }

    /// @notice Verifies createPolicy panics with arithmetic overflow when the counter is at uint56 max.
    /// @dev    Slot-writes nextCounter to type(uint56).max to avoid iterating 2^56 times.
    ///         Mock-only: `vm.store` cannot write to native precompile addresses, so this
    ///         test is skipped when running against live precompiles.
    ///         Matches the Rust precompile which reverts with Panic(UnderOverflow) = Panic(0x11).
    function test_createPolicy_revert_counterOverflow(address caller, address admin_, uint8 typeIdx) public {
        vm.skip(livePrecompiles);

        _assumeValidCaller(caller);
        vm.assume(admin_ != address(0));
        IPolicyRegistry.PolicyType pt = _creatablePolicyType(typeIdx);

        vm.store(
            address(policyRegistry), MockPolicyRegistryStorage.nextCounterSlot(), bytes32(uint256(type(uint56).max))
        );

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(caller);
        policyRegistry.createPolicy(admin_, pt);
    }
}
