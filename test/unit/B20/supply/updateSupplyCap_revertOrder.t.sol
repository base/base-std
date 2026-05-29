// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `updateSupplyCap`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(DEFAULT_ADMIN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. INVALID-SUPPLY-CAP (`newSupplyCap < currentSupply`) → `InvalidSupplyCap`
///
///         C(2, 2) = 1 pair.
contract B20UpdateSupplyCapRevertOrderTest is B20Test {
    /// @notice ROLE beats INVALID-SUPPLY-CAP.
    /// @dev Caller lacks DEFAULT_ADMIN_ROLE AND the requested cap is below the current supply.
    ///      Role modifier fires before the body's cap invariant check.
    function test_updateSupplyCap_revertOrder_role_beats_invalidCap(address caller, uint256 mintedAmount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        mintedAmount = bound(mintedAmount, 1, type(uint128).max);
        _mint(alice, mintedAmount);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updateSupplyCap(0); // any cap below totalSupply triggers InvalidSupplyCap
    }
}
