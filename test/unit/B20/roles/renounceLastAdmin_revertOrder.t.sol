// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `renounceLastAdmin`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`!$.roles[DEFAULT_ADMIN_ROLE][msg.sender]`) → `AccessControlUnauthorizedAccount`
///         2. NOT-SOLE-ADMIN (`$.adminCount != 1`) → `NotSoleAdmin`
///
///         C(2, 2) = 1 pair.
contract B20RenounceLastAdminRevertOrderTest is B20Test {
    /// @notice ROLE beats NOT-SOLE-ADMIN.
    /// @dev Caller does NOT have DEFAULT_ADMIN_ROLE AND adminCount > 1 (a second admin exists).
    ///      Role check fires before the sole-admin invariant.
    function test_renounceLastAdmin_revertOrder_role_beats_notSoleAdmin(address caller, address otherAdmin) public {
        _assumeValidCaller(caller);
        _assumeValidActor(otherAdmin);
        vm.assume(caller != admin);
        vm.assume(otherAdmin != admin);
        vm.assume(otherAdmin != caller);
        _grantRole(B20Constants.DEFAULT_ADMIN_ROLE, otherAdmin); // adminCount == 2

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.renounceLastAdmin();
    }
}
