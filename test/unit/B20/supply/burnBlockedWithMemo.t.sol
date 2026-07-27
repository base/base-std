// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Unit tests for `burnBlockedWithMemo` (burn-based seize with memo).
///
/// @notice Unlike the legacy `burnBlocked`, this variant is part of the seize operation class:
///         it gates on the SEIZE pause vector and the SEIZABLE_POLICY (not BURN / TRANSFER_SENDER).
contract B20BurnBlockedWithMemoTest is B20Test {
    /// @notice Reverts when caller lacks BURN_BLOCKED_ROLE.
    function test_burnBlockedWithMemo_revert_unauthorized(address caller, address from, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_BLOCKED_ROLE
            )
        );
        token.burnBlockedWithMemo(from, amount, bytes32(0));
    }

    /// @notice Reverts when the SEIZE feature is paused (not BURN).
    function test_burnBlockedWithMemo_revert_whenSeizePaused(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        _setPolicy(B20Constants.SEIZABLE_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _pause(IB20.PausableFeature.SEIZE);

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.burnBlockedWithMemo(from, amount, bytes32(0));
    }

    /// @notice Reverts AccountNotBlocked when `from` is authorized under SEIZABLE_POLICY.
    function test_burnBlockedWithMemo_revert_accountNotBlocked(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        // Default SEIZABLE_POLICY is ALWAYS_ALLOW (0) → every address authorized → not blocked.

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotBlocked.selector, from));
        token.burnBlockedWithMemo(from, amount, bytes32(0));
    }

    /// @notice Reverts InsufficientBalance when the target balance is below `amount`.
    function test_burnBlockedWithMemo_revert_insufficientBalance(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 1, type(uint256).max);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        _setPolicy(B20Constants.SEIZABLE_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.burnBlockedWithMemo(from, amount, bytes32(0));
    }

    /// @notice Debits the target and decreases totalSupply by `amount`.
    function test_burnBlockedWithMemo_success_debitsAndDecreasesSupply(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _setPolicy(B20Constants.SEIZABLE_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        uint256 before = token.totalSupply();

        vm.prank(burnBlocker);
        token.burnBlockedWithMemo(from, amount, bytes32(0));

        assertEq(token.balanceOf(from), 0, "target balance must be zero after seizure");
        assertEq(token.totalSupply(), before - amount, "totalSupply must decrease by seized amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            before - amount,
            "totalSupply slot must reflect the seizure"
        );
    }

    /// @notice Emits Transfer(from, 0, amount), BurnedBlocked(caller, from, amount), then Memo(caller, memo).
    function test_burnBlockedWithMemo_success_emitsTransferBurnedBlockedAndMemo(
        address from,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _setPolicy(B20Constants.SEIZABLE_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, address(0), amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.BurnedBlocked(burnBlocker, from, amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Memo(burnBlocker, memo);
        vm.prank(burnBlocker);
        token.burnBlockedWithMemo(from, amount, memo);
    }
}
