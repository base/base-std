// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

import {PolicyRegistryTest} from "base-std-test/lib/PolicyRegistryTest.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract PolicyRegistryIsAuthorizedTest is PolicyRegistryTest {
    /// @notice Verifies isAuthorized on an uncreated ALLOWLIST id returns false
    /// @dev Documents empty-member-set semantics: no existence check, so an
    ///      empty allowlist authorizes no one.
    function test_isAuthorized_success_uncreatedAllowlistReturnsFalse(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 policyId = (uint64(uint8(IPolicyRegistry.PolicyType.ALLOWLIST)) << 56) | uint64(counter);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized on an uncreated BLOCKLIST id returns true
    /// @dev Empty-member-set semantics: an empty blocklist blocks no one.
    function test_isAuthorized_success_uncreatedBlocklistReturnsTrue(uint56 counter, address account) public view {
        vm.assume(counter > 1);
        uint64 policyId = (uint64(uint8(IPolicyRegistry.PolicyType.BLOCKLIST)) << 56) | uint64(counter);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns false for any id whose top byte
    ///         is outside the PolicyType enum range.
    /// @dev Malformed-ID short-circuit returns false rather than reverting.
    function test_isAuthorized_success_falseForMalformedId(uint64 seed, address account) public view {
        uint64 policyId = _malformedPolicyId(seed);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns true for any account under ALWAYS_ALLOW_ID
    /// @dev Built-in sentinel semantics: ALWAYS_ALLOW_ID returns true unconditionally
    function test_isAuthorized_success_alwaysAllowBuiltin(address account) public view {
        assertTrue(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_ALLOW_ID, account));
    }

    /// @notice Verifies isAuthorized returns false for any account under ALWAYS_BLOCK_ID
    /// @dev Built-in sentinel semantics: ALWAYS_BLOCK_ID returns false unconditionally
    function test_isAuthorized_success_alwaysBlockBuiltin(address account) public view {
        assertFalse(policyRegistry.isAuthorized(PolicyRegistryConstants.ALWAYS_BLOCK_ID, account));
    }

    /// @notice Verifies isAuthorized returns true for an allowlist member
    /// @dev Allowlist semantics: membership grants authorization
    function test_isAuthorized_success_allowlistMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateAllowlist(policyId, true, accounts);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns false for a non-member of an allowlist
    /// @dev Allowlist semantics: absence denies authorization
    function test_isAuthorized_success_allowlistNonMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns false for a blocklist member
    /// @dev Blocklist semantics: membership denies authorization
    function test_isAuthorized_success_blocklistMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateBlocklist(policyId, true, accounts);
        assertFalse(policyRegistry.isAuthorized(policyId, account));
    }

    /// @notice Verifies isAuthorized returns true for a non-member of a blocklist
    /// @dev Blocklist semantics: absence grants authorization
    function test_isAuthorized_success_blocklistNonMember(address account) public {
        uint64 policyId = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        assertTrue(policyRegistry.isAuthorized(policyId, account));
    }

    // ============================================================
    //                  COMPOSITE POLICY SEMANTICS
    // ============================================================
    // UNION is OR: authorized if ANY child authorizes.
    // INTERSECT is AND: authorized only if EVERY child authorizes.
    // Composites reference their children live — evaluation reads current
    // child membership, not a snapshot taken at composite-creation time.

    /// @notice Sets membership of a single `account` on a simple policy, as `admin`.
    function _setAllowlistMember(uint64 policyId, address account, bool member) private {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(admin);
        policyRegistry.updateAllowlist(policyId, member, accounts);
    }

    /// @notice Verifies UNION authorizes an account that is a member of any single child
    /// @dev OR semantics: `account` is on allowlist A only, yet the UNION authorizes it.
    function test_isAuthorized_success_union_anyChildAuthorizes(address account) public {
        uint64 childA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 composite =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(childA, childB));
        _setAllowlistMember(childA, account, true);
        assertTrue(policyRegistry.isAuthorized(composite, account));
    }

    /// @notice Verifies UNION denies an account that no child authorizes
    /// @dev OR semantics: `account` is on neither empty allowlist, so the UNION denies it.
    function test_isAuthorized_success_union_noChildAuthorizes(address account) public {
        uint64 childA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 composite =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(childA, childB));
        assertFalse(policyRegistry.isAuthorized(composite, account));
    }

    /// @notice Verifies INTERSECT authorizes an account only when every child authorizes it
    /// @dev AND semantics: `account` is on both allowlists, so the INTERSECT authorizes it.
    function test_isAuthorized_success_intersect_allChildrenAuthorize(address account) public {
        uint64 childA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(childA, childB)
        );
        _setAllowlistMember(childA, account, true);
        _setAllowlistMember(childB, account, true);
        assertTrue(policyRegistry.isAuthorized(composite, account));
    }

    /// @notice Verifies INTERSECT denies an account when even one child denies it
    /// @dev AND semantics: `account` is on allowlist A only, so the INTERSECT denies it.
    function test_isAuthorized_success_intersect_oneChildDenies(address account) public {
        uint64 childA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 composite = policyRegistry.createCompositePolicy(
            admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(childA, childB)
        );
        _setAllowlistMember(childA, account, true);
        assertFalse(policyRegistry.isAuthorized(composite, account));
    }

    /// @notice Verifies composite gates combine mixed ALLOWLIST + BLOCKLIST children correctly
    /// @dev With `account` absent from both children, the allowlist denies and the blocklist allows:
    ///      UNION → true (OR), INTERSECT → false (AND). Exercises both simple semantics under a gate.
    function test_isAuthorized_success_composite_mixedChildTypes(address account) public {
        uint64 allow = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 block_ = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
        uint64 union =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(allow, block_));
        uint64 intersect =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.INTERSECT, _childIds(allow, block_));

        // account absent: allowlist denies, blocklist allows.
        assertTrue(policyRegistry.isAuthorized(union, account), "UNION(deny, allow) must be true");
        assertFalse(policyRegistry.isAuthorized(intersect, account), "INTERSECT(deny, allow) must be false");
    }

    /// @notice Verifies composite evaluation tracks live child membership changes
    /// @dev A UNION over two empty allowlists denies `account`; adding `account` to a child
    ///      flips the composite to authorize — composites reference children, not snapshots.
    function test_isAuthorized_success_composite_reflectsChildMembershipChange(address account) public {
        uint64 childA = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 childB = policyRegistry.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
        uint64 composite =
            policyRegistry.createCompositePolicy(admin, IPolicyRegistry.PolicyType.UNION, _childIds(childA, childB));

        assertFalse(policyRegistry.isAuthorized(composite, account));
        _setAllowlistMember(childB, account, true);
        assertTrue(policyRegistry.isAuthorized(composite, account));
    }
}
