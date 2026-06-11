// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20BurnBlockedTest is B20Test {
    /// @notice Verifies burnBlocked reverts when caller lacks BURN_BLOCKED_ROLE
    /// @dev Access control: only role-holders can seize balance; checks AccessControlUnauthorizedAccount
    function test_burnBlocked_revert_unauthorized(address caller, address from, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_BLOCKED_ROLE
            )
        );
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked reverts when BURN feature is paused
    /// @dev Pause guard; checks ContractPaused(BURN) error
    function test_burnBlocked_revert_whenBurnPaused(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        // We also need TRANSFER_SENDER_POLICY set to ALWAYS_BLOCK_ID so the from-not-authorized
        // path is satisfied; otherwise the policy check inside burnBlocked fires
        // with AccountNotBlocked first.
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _pause(IB20.PausableFeature.BURN);

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked reverts when the target is authorized under TRANSFER_SENDER_POLICY
    /// @dev Seizure is only permitted against policy-blocked addresses; checks AccountNotBlocked(from)
    function test_burnBlocked_revert_accountNotBlocked(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        // Default TRANSFER_SENDER_POLICY is ALWAYS_ALLOW_ID (0), so every address is "authorized" → not blocked.

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotBlocked.selector, from));
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked reverts when target balance is insufficient
    /// @dev Balance precondition; checks InsufficientBalance(from, balance, amount)
    function test_burnBlocked_revert_insufficientBalance(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 1, type(uint256).max);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID); // from is policy-blocked

        // from has zero balance.
        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.burnBlocked(from, amount);
    }

    /// @notice Verifies burnBlocked debits the target balance by amount
    /// @dev Accounting: balanceOf(from) decreases by exactly amount.
    ///      Paired slot assertion verifies `balances[from]` slot reflects the seizure.
    function test_burnBlocked_success_debitsTarget(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        // Mint while no policy is set so the mint isn't blocked.
        _mint(from, amount);
        // Now block from via TRANSFER_SENDER_POLICY policy, then seize.
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);

        vm.prank(burnBlocker);
        token.burnBlocked(from, amount);
        assertEq(token.balanceOf(from), 0, "target balance must be zero after seizure");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            0,
            "balances[from] slot must reflect the seizure"
        );
    }

    /// @notice Verifies burnBlocked decreases totalSupply by amount
    /// @dev Accounting: totalSupply tracks cumulative minted-burned.
    ///      Paired slot assertion verifies `totalSupply` slot reflects the decrease.
    function test_burnBlocked_success_decreasesTotalSupply(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        uint256 before = token.totalSupply();

        vm.prank(burnBlocker);
        token.burnBlocked(from, amount);
        assertEq(token.totalSupply(), before - amount, "totalSupply must decrease by seized amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            before - amount,
            "totalSupply slot must reflect the seizure"
        );
    }

    /// @notice Verifies burnBlocked emits Transfer(from, address(0), amount) and BurnedBlocked(caller, from, amount)
    /// @dev Dual-event integrity: Transfer for accounting, BurnedBlocked for seizure audit trail
    function test_burnBlocked_success_emitsTransferAndBurnedBlocked(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, address(0), amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.BurnedBlocked(burnBlocker, from, amount);
        vm.prank(burnBlocker);
        token.burnBlocked(from, amount);
    }
}
