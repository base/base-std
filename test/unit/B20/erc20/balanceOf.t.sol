// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20BalanceOfTest is B20Test {
    /// @notice Verifies balanceOf returns zero for any account that has never received tokens
    /// @dev Default state across the address space
    function test_balanceOf_success_zeroForUntouchedAccount(address account) public {
        // unimplemented
    }

    /// @notice Verifies balanceOf returns the amount credited via mint
    /// @dev Mint readback; canonical mint test lives in mint.t.sol
    function test_balanceOf_success_reflectsMint(address to, uint256 amount) public {
        // unimplemented
    }

    /// @notice Verifies balanceOf reflects the post-transfer state for sender and receiver
    /// @dev Transfer readback; canonical transfer test lives in transfer.t.sol
    function test_balanceOf_success_reflectsTransfer(address from, address to, uint256 amount) public {
        // unimplemented
    }
}
