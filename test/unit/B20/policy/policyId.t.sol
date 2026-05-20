// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20PolicyIdTest is B20Test {
    /// @notice Verifies policyId returns 0 (always-allow built-in) for any supported slot before configuration
    /// @dev Default state: newly-created tokens are unrestricted across all supported policy slots
    function test_policyId_success_zeroByDefault(uint8 typeIdx) public view {
        bytes32 policyType = _knownPolicyType(typeIdx);
        assertEq(
            token.policyId(policyType),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "unconfigured supported slot must default to ALWAYS_ALLOW_ID (0)"
        );
    }

    /// @notice Verifies policyId returns the value most recently set via updatePolicy
    /// @dev Read-after-write across all supported policy types
    function test_policyId_success_reflectsUpdatePolicy(uint8 typeIdx, uint64 newPolicyId) public {
        bytes32 policyType = _knownPolicyType(typeIdx);
        // MockPolicyRegistry only knows the two built-in sentinel ids.
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;
        _setPolicy(policyType, newPolicyId);
        assertEq(token.policyId(policyType), newPolicyId, "slot must reflect updatePolicy");
    }

    /// @notice Verifies policyId returns 0 for an unsupported policyType (no fallback storage).
    /// @dev Reading an unsupported type is observably equivalent to reading an unconfigured
    ///      supported type — both return ALWAYS_ALLOW_ID. Writes are the strict operation
    ///      (they revert UnsupportedPolicyType); reads stay silent.
    function test_policyId_success_zeroForUnknownType(bytes32 policyType) public view {
        vm.assume(!_isKnownPolicyType(policyType));
        assertEq(
            token.policyId(policyType),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "unsupported policyType read must return 0"
        );
    }
}
