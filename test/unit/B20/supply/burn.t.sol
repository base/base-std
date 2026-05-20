// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

contract B20BurnTest is B20Test {
    /// @notice Verifies burn reverts when caller lacks BURN_ROLE
    /// @dev Access control: only role-holders can burn; checks AccessControlUnauthorizedAccount
    function test_burn_revert_unauthorized(address caller, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_ROLE)
        );
        token.burn(amount);
    }

    /// @notice Verifies burn reverts when BURN feature is paused
    /// @dev Pause guard; checks ContractPaused(BURN) error
    function test_burn_revert_whenBurnPaused(uint256 amount) public {
        _grantRole(B20Constants.BURN_ROLE, burner);
        _pause(IB20.PausableFeature.BURN);

        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        token.burn(amount);
    }

    /// @notice Verifies burn reverts when caller balance is insufficient
    /// @dev Balance precondition; checks InsufficientBalance(caller, balance, amount)
    function test_burn_revert_insufficientBalance(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);
        _grantRole(B20Constants.BURN_ROLE, burner);
        // burner has zero balance; any positive amount exceeds it.

        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, burner, 0, amount));
        token.burn(amount);
    }

    /// @notice Verifies burn debits the caller's balance by amount
    /// @dev Accounting: balanceOf(caller) decreases by exactly amount
    function test_burn_success_debitsCaller(uint256 amount) public {
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);

        vm.prank(burner);
        token.burn(amount);
        assertEq(token.balanceOf(burner), 0, "burner balance must be zero after full burn");
    }

    /// @notice Verifies burn decreases totalSupply by amount
    /// @dev Accounting: totalSupply tracks cumulative minted-burned
    function test_burn_success_decreasesTotalSupply(uint256 amount) public {
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);
        uint256 before = token.totalSupply();

        vm.prank(burner);
        token.burn(amount);
        assertEq(token.totalSupply(), before - amount, "totalSupply must decrease by burned amount");
    }

    /// @notice Verifies burn emits Transfer(caller, address(0), amount)
    /// @dev Event integrity for the burn path; burn represented as transfer to the zero address
    function test_burn_success_emitsTransferToZero(uint256 amount) public {
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(burner, address(0), amount);
        vm.prank(burner);
        token.burn(amount);
    }
}
