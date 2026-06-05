// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Sequential check-order test for `unpause`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(UNPAUSE_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. EMPTY-SET (`features.length == 0`) → `EmptyFeatureSet`
///
///         The single test below activates both violations simultaneously,
///         then fixes them one at a time in canonical order, asserting that
///         the next-priority revert fires at each step.
contract B20UnpauseRevertOrderTest is B20Test {
    function test_unpause_revertOrder(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        IB20.PausableFeature[] memory empty = new IB20.PausableFeature[](0);

        // Both conditions active: caller lacks UNPAUSE_ROLE, features is empty.

        // 1. ROLE fires first (empty-set also violated).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.UNPAUSE_ROLE)
        );
        token.unpause(empty);
        _grantRole(B20Constants.UNPAUSE_ROLE, caller);

        // 2. EMPTY-SET fires (role cleared; features still empty).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.EmptyFeatureSet.selector));
        token.unpause(empty);

        // Success — all conditions satisfied.
        _pause(IB20.PausableFeature.TRANSFER);
        vm.prank(caller);
        token.unpause(_singleFeature(IB20.PausableFeature.TRANSFER));
    }
}
