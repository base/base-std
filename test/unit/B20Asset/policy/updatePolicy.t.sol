// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20AssetUpdatePolicyTest is B20AssetTest {
    /// @notice Verifies updatePolicy still routes base policy types through the inherited write path on the asset variant.
    /// @dev The asset variant adds no extra policy slots of its own; this is a sanity check that
    ///      the base `updatePolicy` path still works end-to-end (write then readback) for a base
    ///      scope. ALWAYS_BLOCK sentinel avoids registering a custom policy.
    function test_updatePolicy_success_baseTypesStillRouteThroughSuper() public {
        vm.prank(admin);
        token.updatePolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(
            token.policyId(B20Constants.TRANSFER_SENDER_POLICY),
            PolicyRegistryConstants.ALWAYS_BLOCK_ID,
            "TRANSFER_SENDER write must persist"
        );
    }
}
