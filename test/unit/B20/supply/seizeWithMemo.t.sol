// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Unit tests for `seizeWithMemo` (transfer-based seize).
contract B20SeizeWithMemoTest is B20Test {
    address internal seizer = makeAddr("seizer");

    /// @dev Blocks `from` under SEIZE_HOLDER_POLICY and grants the seize role. Mirrors the
    ///      setup every success path shares.
    function _armSeize() internal {
        _grantRole(B20Constants.SEIZE_ROLE, seizer);
        _setPolicy(B20Constants.SEIZE_HOLDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
    }

    /// @notice Reverts when caller lacks SEIZE_ROLE.
    function test_seizeWithMemo_revert_unauthorized(address caller, address from, address to, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.SEIZE_ROLE)
        );
        token.seizeWithMemo(from, to, amount, bytes32(0));
    }

    /// @notice Reverts when the SEIZE feature is paused.
    function test_seizeWithMemo_revert_whenSeizePaused(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _armSeize();
        _pause(IB20.PausableFeature.SEIZE);

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.seizeWithMemo(from, to, amount, bytes32(0));
    }

    /// @notice Reverts with InvalidReceiver when `to == address(0)`.
    function test_seizeWithMemo_revert_invalidReceiver(address from, uint256 amount) public {
        _assumeValidActor(from);
        _armSeize();

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.seizeWithMemo(from, address(0), amount, bytes32(0));
    }

    /// @notice Reverts AccountNotSeizable when `from` is authorized under SEIZE_HOLDER_POLICY.
    /// @dev Default SEIZE_HOLDER_POLICY is ALWAYS_ALLOW (0) → every account authorized → not seizable.
    function test_seizeWithMemo_revert_accountNotBlocked(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        _grantRole(B20Constants.SEIZE_ROLE, seizer);

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotSeizable.selector, from));
        token.seizeWithMemo(from, to, amount, bytes32(0));
    }

    /// @notice Reverts InsufficientBalance when the seized account's balance is below `amount`.
    function test_seizeWithMemo_revert_insufficientBalance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, type(uint256).max);
        _armSeize();

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.seizeWithMemo(from, to, amount, bytes32(0));
    }

    /// @notice Moves the seized balance from `from` to `to` and leaves totalSupply unchanged.
    function test_seizeWithMemo_success_movesBalance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _armSeize();
        uint256 supplyBefore = token.totalSupply();

        vm.prank(seizer);
        token.seizeWithMemo(from, to, amount, bytes32(0));

        assertEq(token.balanceOf(from), 0, "seized account must be drained");
        assertEq(token.balanceOf(to), amount, "destination must receive the seized amount");
        assertEq(token.totalSupply(), supplyBefore, "seize is a transfer: totalSupply is unchanged");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            amount,
            "balances[to] slot must reflect the seizure"
        );
    }

    /// @notice Succeeds even when `to` is blocked by TRANSFER_RECEIVER_POLICY: seize is an admin
    ///         operation and does not consult the receiver policy on the destination.
    function test_seizeWithMemo_success_ignoresReceiverPolicy(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _armSeize();
        // A normal transfer to `to` would revert PolicyForbids(TRANSFER_RECEIVER_POLICY, ...).
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(seizer);
        token.seizeWithMemo(from, to, amount, bytes32(0));

        assertEq(token.balanceOf(to), amount, "seize must succeed regardless of receiver policy on `to`");
    }

    /// @notice Requires no allowance from the seized account: seize skips allowance accounting.
    function test_seizeWithMemo_success_noAllowanceRequired(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _armSeize();
        // No approve() from `from` to `seizer`; a normal transferFrom would revert InsufficientAllowance.

        vm.prank(seizer);
        token.seizeWithMemo(from, to, amount, bytes32(0));

        assertEq(token.balanceOf(to), amount, "seize must not require an allowance");
        assertEq(token.allowance(from, seizer), 0, "no allowance should be consumed");
    }

    /// @notice Emits, in order, Transfer, Memo (immediately after Transfer per the IB20 invariant), then Seized.
    function test_seizeWithMemo_success_emitsEvents(address from, address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _mint(from, amount);
        _armSeize();

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Memo(seizer, memo);
        vm.expectEmit(true, true, true, true, address(token));
        emit IB20.Seized(seizer, from, to, amount);
        vm.prank(seizer);
        token.seizeWithMemo(from, to, amount, memo);
    }
}
