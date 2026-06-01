// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `pause`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(PAUSE_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. EMPTY-SET (`features.length == 0`) → `EmptyFeatureSet`
///
///         C(2, 2) = 1 pair. The role modifier runs before the body's
///         empty-set guard.
contract B20PauseRevertOrderTest is B20Test {
    /// @notice ROLE beats EMPTY-SET.
    /// @dev Caller lacks PAUSE_ROLE AND features is empty — role check fires first.
    function test_pause_revertOrder_role_beats_emptyFeatureSet(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        IB20.PausableFeature[] memory empty = new IB20.PausableFeature[](0);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.PAUSE_ROLE)
        );
        token.pause(empty);
    }
}
