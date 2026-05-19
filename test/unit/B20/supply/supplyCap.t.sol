// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20SupplyCapTest is B20Test {
    /// @notice Verifies supplyCap returns the value set at token creation
    /// @dev Constructor-stored value readback
    function test_supplyCap_success_returnsCreationCap() public {
        // unimplemented
    }

    /// @notice Verifies supplyCap reflects updates made via setSupplyCap
    /// @dev Mutable cap readback; canonical setter test lives in setSupplyCap.t.sol
    function test_supplyCap_success_reflectsSetSupplyCap(uint256 newCap) public {
        // unimplemented
    }
}
