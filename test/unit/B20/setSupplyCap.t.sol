// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20SetSupplyCapTest is B20Test {
    /// @notice Verifies setSupplyCap reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only admin may resize the cap; checks AccessControlUnauthorizedAccount
    function test_setSupplyCap_revert_unauthorized(address caller, uint256 newCap) public {
        // unimplemented
    }

    /// @notice Verifies setSupplyCap reverts when newCap is below the current totalSupply
    /// @dev Invariant: never invalidate already-issued supply; checks InvalidSupplyCap(currentSupply, proposedCap)
    function test_setSupplyCap_revert_belowCurrentSupply(uint256 mintedAmount, uint256 newCap) public {
        // unimplemented
    }

    /// @notice Verifies setSupplyCap raises the cap to a value above the current totalSupply
    /// @dev Read-after-write: supplyCap returns newCap
    function test_setSupplyCap_success_raisesCap(uint256 newCap) public {
        // unimplemented
    }

    /// @notice Verifies setSupplyCap lowers the cap to a value at or above the current totalSupply
    /// @dev Cap may be lowered as long as totalSupply <= newCap
    function test_setSupplyCap_success_lowersCap(uint256 newCap) public {
        // unimplemented
    }

    /// @notice Verifies setSupplyCap emits SupplyCapUpdated(updater, oldCap, newCap)
    /// @dev Event integrity; canonical SupplyCapUpdated emission test
    function test_setSupplyCap_success_emitsSupplyCapUpdated(uint256 newCap) public {
        // unimplemented
    }
}
