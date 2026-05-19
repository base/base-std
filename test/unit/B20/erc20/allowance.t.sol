// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20AllowanceTest is B20Test {
    /// @notice Verifies allowance returns zero for any unconfigured (owner, spender) pair
    /// @dev Default state across the address space
    function test_allowance_success_zeroByDefault(address owner, address spender) public {
        // unimplemented
    }

    /// @notice Verifies allowance reflects the value set via approve
    /// @dev Approval readback; canonical approve test lives in approve.t.sol
    function test_allowance_success_reflectsApprove(address owner, address spender, uint256 amount) public {
        // unimplemented
    }

    /// @notice Verifies allowance reflects the value set via permit
    /// @dev Permit readback; canonical permit test lives in permit.t.sol
    function test_allowance_success_reflectsPermit(uint256 ownerPrivateKey, address spender, uint256 amount) public {
        // unimplemented
    }

    /// @notice Verifies allowance decreases after a successful transferFrom
    /// @dev Spend-tracking readback; canonical transferFrom test lives in transferFrom.t.sol
    function test_allowance_success_decreasesAfterTransferFrom(
        address owner,
        address spender,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        // unimplemented
    }
}
