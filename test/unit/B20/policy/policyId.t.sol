// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20PolicyIdTest is B20Test {
    /// @notice Verifies policyId returns 0 (always-allow built-in) for any supported slot before configuration
    /// @dev Default state: newly-created tokens are unrestricted across all supported policy slots
    function test_policyId_success_zeroByDefault(uint8 typeIdx) public view {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        assertEq(
            token.policyId(policyScope),
            PolicyRegistryConstants.ALWAYS_ALLOW_ID,
            "unconfigured supported slot must default to ALWAYS_ALLOW_ID (0)"
        );
    }

    /// @notice Verifies policyId returns the value most recently set via updatePolicy
    /// @dev Read-after-write across all supported policy types
    function test_policyId_success_reflectsUpdatePolicy(uint8 typeIdx, uint64 newPolicyId) public {
        bytes32 policyScope = _knownPolicyType(typeIdx);
        // MockPolicyRegistry only knows the two built-in sentinel ids.
        newPolicyId =
            newPolicyId % 2 == 0 ? PolicyRegistryConstants.ALWAYS_ALLOW_ID : PolicyRegistryConstants.ALWAYS_BLOCK_ID;
        _setPolicy(policyScope, newPolicyId);
        assertEq(token.policyId(policyScope), newPolicyId, "slot must reflect updatePolicy");
    }

    /// @notice Verifies policyId reverts UnsupportedPolicyType for any policyScope
    ///         outside the token's supported set.
    /// @dev Reads are strict: there is no fallback storage, and silently returning
    ///      0 (ALWAYS_ALLOW) for an unsupported type would let a typo'd query
    ///      masquerade as "no restriction". Both reads and writes revert symmetrically.
    function test_policyId_revert_unsupportedPolicyType(bytes32 policyScope) public {
        vm.assume(!_isKnownPolicyType(policyScope));
        vm.expectRevert(abi.encodeWithSelector(IB20.UnsupportedPolicyType.selector, policyScope));
        token.policyId(policyScope);
    }
}
