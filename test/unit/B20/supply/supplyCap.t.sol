// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20SupplyCapTest is B20Test {
    /// @notice Verifies supplyCap returns the value set at token creation
    /// @dev Constructor-stored value readback. The factory writes B20Constants.MAX_SUPPLY_CAP
    ///      at bootstrap, so a fresh default token starts uncapped (uint128.max is the
    ///      unbounded sentinel and the maximum the cap may ever hold).
    function test_supplyCap_success_returnsCreationCap() public view {
        assertEq(token.supplyCap(), B20Constants.MAX_SUPPLY_CAP, "fresh token must start with unbounded cap");
    }

    /// @notice Verifies supplyCap reflects updates made via updateSupplyCap
    /// @dev Mutable cap readback; canonical setter test lives in updateSupplyCap.t.sol
    function test_supplyCap_success_reflectsSetSupplyCap(uint256 newCap) public {
        newCap = bound(newCap, 0, B20Constants.MAX_SUPPLY_CAP);
        vm.prank(admin);
        token.updateSupplyCap(newCap);
        assertEq(token.supplyCap(), newCap, "supplyCap must reflect updateSupplyCap");
    }
}
