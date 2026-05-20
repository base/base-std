// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20SupplyCapTest is B20Test {
    /// @notice Verifies supplyCap returns the value set at token creation
    /// @dev Constructor-stored value readback. The factory writes type(uint256).max
    ///      at bootstrap, so a fresh default token starts uncapped.
    function test_supplyCap_success_returnsCreationCap() public view {
        assertEq(token.supplyCap(), type(uint256).max, "fresh token must start with unbounded cap");
    }

    /// @notice Verifies supplyCap reflects updates made via setSupplyCap
    /// @dev Mutable cap readback; canonical setter test lives in setSupplyCap.t.sol
    function test_supplyCap_success_reflectsSetSupplyCap(uint256 newCap) public {
        vm.prank(admin);
        token.setSupplyCap(newCap);
        assertEq(token.supplyCap(), newCap, "supplyCap must reflect setSupplyCap");
    }
}
