// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistryTest} from "test/lib/PolicyRegistryTest.sol";

contract PolicyRegistryCreatePolicyTest is PolicyRegistryTest {
    /// @notice Verifies createPolicy reverts when admin is the zero address
    /// @dev Required-field guard; checks ZeroAddress() error
    function test_createPolicy_revert_zeroAdmin(address caller, uint8 policyTypeInt) public {
        // unimplemented
    }

    /// @notice Verifies createPolicy reverts for any policyType value outside the enum
    /// @dev Fuzz confirms only ALLOWLIST / BLOCKLIST are accepted; checks InvalidPolicyType() error
    function test_createPolicy_revert_invalidPolicyType(address caller, address admin_, uint8 policyTypeInt) public {
        // unimplemented
    }

    /// @notice Verifies createPolicy assigns a fresh allowlist policy id
    /// @dev Type, admin, and existence all readable post-creation
    function test_createPolicy_success_allowlist(address caller, address admin_) public {
        // unimplemented
    }

    /// @notice Verifies createPolicy assigns a fresh blocklist policy id
    /// @dev Type, admin, and existence all readable post-creation
    function test_createPolicy_success_blocklist(address caller, address admin_) public {
        // unimplemented
    }

    /// @notice Verifies the returned policy id advances nextPolicyId monotonically
    /// @dev Sequential creations produce sequential, non-overlapping ids
    function test_createPolicy_success_advancesNextPolicyId(address caller, address admin_, uint8 typeA, uint8 typeB)
        public
    {
        // unimplemented
    }

    /// @notice Verifies createPolicy emits PolicyCreated with the correct args
    /// @dev Event integrity: policyId, creator, policyType match the call
    function test_createPolicy_success_emitsPolicyCreated(address caller, address admin_, uint8 policyTypeInt) public {
        // unimplemented
    }

    /// @notice Verifies createPolicy emits PolicyAdminUpdated(previousAdmin = 0) on initial assignment
    /// @dev Initial-admin variant of PolicyAdminUpdated; canonical event test lives in finalizeUpdateAdmin.t.sol
    function test_createPolicy_success_emitsInitialPolicyAdminUpdated(
        address caller,
        address admin_,
        uint8 policyTypeInt
    ) public {
        // unimplemented
    }
}
