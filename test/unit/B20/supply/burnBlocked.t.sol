// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20BurnBlockedTest is B20Test {
    /// @notice Verifies burnBlocked reverts when caller lacks BURN_BLOCKED_ROLE
    /// @dev Access control: only role-holders can seize balance; checks AccessControlUnauthorizedAccount
    function test_burnBlocked_revert_unauthorized(address caller, address from, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, BURN_BLOCKED_ROLE)
        );
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked reverts when BURN feature is paused
    /// @dev Pause guard; checks ContractPaused(BURN) error
    function test_burnBlocked_revert_whenBurnPaused(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(BURN_BLOCKED_ROLE, burnBlocker);
        // We also need TRANSFER_SENDER set to ALWAYS_REJECT so the from-not-authorized
        // path is satisfied; otherwise the policy check inside burnBlocked fires
        // with AccountNotBlocked first.
        _setPolicy(TRANSFER_SENDER, ALWAYS_REJECT);
        _pause(IB20.PausableFeature.BURN);

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked reverts when the target is authorized under TRANSFER_SENDER
    /// @dev Seizure is only permitted against policy-blocked addresses; checks AccountNotBlocked(from)
    function test_burnBlocked_revert_accountNotBlocked(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(BURN_BLOCKED_ROLE, burnBlocker);
        // Default TRANSFER_SENDER is ALWAYS_ALLOW (0), so every address is "authorized" → not blocked.

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotBlocked.selector, from));
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked reverts when target balance is insufficient
    /// @dev Balance precondition; checks InsufficientBalance(from, balance, amount)
    function test_burnBlocked_revert_insufficientBalance(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 1, type(uint256).max);
        _grantRole(BURN_BLOCKED_ROLE, burnBlocker);
        _setPolicy(TRANSFER_SENDER, ALWAYS_REJECT); // from is policy-blocked

        // from has zero balance.
        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked debits the target balance by amount
    /// @dev Accounting: balanceOf(from) decreases by exactly amount
    function test_burnBlocked_success_debitsTarget(address from, uint256 amount) public {
        _assumeValidActor(from);
        // Mint while no policy is set so the mint isn't blocked.
        _mint(from, amount);
        // Now block from via TRANSFER_SENDER policy, then seize.
        _setPolicy(TRANSFER_SENDER, ALWAYS_REJECT);
        _grantRole(BURN_BLOCKED_ROLE, burnBlocker);

        vm.prank(burnBlocker);
        token.burnBlocked(from, amount);
        assertEq(token.balanceOf(from), 0, "target balance must be zero after seizure");
    }

    /// @notice Verifies burnBlocked decreases totalSupply by amount
    /// @dev Accounting: totalSupply tracks cumulative minted-burned
    function test_burnBlocked_success_decreasesTotalSupply(address from, uint256 amount) public {
        _assumeValidActor(from);
        _mint(from, amount);
        _setPolicy(TRANSFER_SENDER, ALWAYS_REJECT);
        _grantRole(BURN_BLOCKED_ROLE, burnBlocker);
        uint256 before = token.totalSupply();

        vm.prank(burnBlocker);
        token.burnBlocked(from, amount);
        assertEq(token.totalSupply(), before - amount, "totalSupply must decrease by seized amount");
    }

    /// @notice Verifies burnBlocked emits Transfer(from, address(0), amount) and BurnedBlocked(caller, from, amount)
    /// @dev Dual-event integrity: Transfer for accounting, BurnedBlocked for seizure audit trail
    function test_burnBlocked_success_emitsTransferAndBurnedBlocked(address from, uint256 amount) public {
        _assumeValidActor(from);
        _mint(from, amount);
        _setPolicy(TRANSFER_SENDER, ALWAYS_REJECT);
        _grantRole(BURN_BLOCKED_ROLE, burnBlocker);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, address(0), amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.BurnedBlocked(burnBlocker, from, amount);
        vm.prank(burnBlocker);
        token.burnBlocked(from, amount);
    }
}
