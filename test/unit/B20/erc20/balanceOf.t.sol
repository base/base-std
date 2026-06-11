// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20BalanceOfTest is B20Test {
    /// @notice Verifies balanceOf returns zero for any account that has never received tokens
    /// @dev Default state across the address space
    function test_balanceOf_success_zeroForUntouchedAccount(address account) public view {
        assertEq(token.balanceOf(account), 0, "untouched account must have zero balance");
    }

    /// @notice Verifies balanceOf returns the amount credited via mint
    /// @dev Mint readback; canonical mint test lives in mint.t.sol
    function test_balanceOf_success_reflectsMint(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(to, amount);
        assertEq(token.balanceOf(to), amount, "balance must equal minted amount");
    }

    /// @notice Verifies balanceOf reflects the post-transfer state for sender and receiver
    /// @dev Transfer readback; canonical transfer test lives in transfer.t.sol
    function test_balanceOf_success_reflectsTransfer(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.transfer(to, amount);

        assertEq(token.balanceOf(from), 0, "from balance must be zero after full transfer");
        assertEq(token.balanceOf(to), amount, "to balance must equal transferred amount");
    }
}
