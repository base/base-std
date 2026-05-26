// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {PolicyRegistry} from "src/impls/PolicyRegistry.sol";
import {IPolicyRegistry} from "src/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

/// @notice Minimal V2 used to verify the upgrade path.
contract PolicyRegistryV2 is PolicyRegistry {
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}

contract PolicyRegistryUpgradeToAndCallTest is PolicyRegistryTest {
    /// @notice The owner can upgrade the implementation and the new logic is live.
    function test_upgradeToAndCall_success_ownerCanUpgrade() public {
        PolicyRegistryV2 newImpl = new PolicyRegistryV2();
        vm.prank(admin);
        PolicyRegistry(address(policyRegistry)).upgradeToAndCall(address(newImpl), "");
        assertEq(PolicyRegistryV2(address(policyRegistry)).version(), "2.0.0");
    }

    /// @notice Existing policy state survives an upgrade.
    function test_upgradeToAndCall_success_statePreservedAcrossUpgrade(address policyAdmin) public {
        vm.assume(policyAdmin != address(0));

        uint64 policyId = _createAllowlist(admin, policyAdmin);

        PolicyRegistryV2 newImpl = new PolicyRegistryV2();
        vm.prank(admin);
        PolicyRegistry(address(policyRegistry)).upgradeToAndCall(address(newImpl), "");

        assertTrue(policyRegistry.policyExists(policyId), "policy must survive upgrade");
        assertEq(policyRegistry.policyAdmin(policyId), policyAdmin, "admin must survive upgrade");
    }

    /// @notice A non-owner caller cannot upgrade the implementation.
    function test_upgradeToAndCall_revert_nonOwnerCannotUpgrade(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        PolicyRegistryV2 newImpl = new PolicyRegistryV2();
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        PolicyRegistry(address(policyRegistry)).upgradeToAndCall(address(newImpl), "");
    }
}
