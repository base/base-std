// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20TransferFromWithMemoTest is B20Test {
    /// @notice Verifies transferFromWithMemo inherits all transferFrom guards
    /// @dev Reuse-of-guards invariant; concrete guard tests live in transferFrom.t.sol.
    ///      We use InsufficientAllowance as the representative guard.
    function test_transferFromWithMemo_revert_inheritsTransferFromGuards(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint256).max);
        // No approval set.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies transferFromWithMemo performs the same balance and allowance updates as transferFrom
    /// @dev Accounting and spend-tracking unchanged from transferFrom.
    ///      Paired slot assertions confirm both balance slots and the
    ///      allowance slot reflect the move and consumption.
    function test_transferFromWithMemo_success_movesBalanceAndDecreasesAllowance(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        // Include amount = 0: the balance/allowance invariants must hold across the full
        // valid input domain, including the no-op zero-transfer case.
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.balanceOf(from), 0, "from must be debited");
        assertEq(token.balanceOf(to), amount, "to must be credited");
        assertEq(token.allowance(from, caller), 0, "allowance must be consumed");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            0,
            "balances[from] slot must reflect the debit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            amount,
            "balances[to] slot must reflect the credit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, caller))),
            0,
            "allowances[from][caller] slot must reflect the consumption"
        );
    }

    /// @notice Verifies transferFromWithMemo emits Transfer then Memo, in that order
    /// @dev Memo is the second log; canonical Memo test for the transferFrom path
    function test_transferFromWithMemo_success_emitsTransferThenMemo(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.expectEmit(true, true, false, false, address(token));
        emit IB20.Memo(caller, memo);
        vm.prank(caller);
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies transferFromWithMemo returns true on success
    /// @dev Matches transferFrom's return-value contract
    function test_transferFromWithMemo_success_returnsTrue(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        assertTrue(token.transferFromWithMemo(from, to, amount, memo), "transferFromWithMemo must return true");
    }

    // ============================================================
    //              REGRESSION: SELF-CALLER ALLOWANCE
    // ============================================================
    //
    // Mirrors the transferFrom regression: msg.sender == from MUST still
    // consume allowance. See transferFrom.t.sol for the canonical
    // regression discussion.

    /// @notice Verifies transferFromWithMemo reverts InsufficientAllowance when caller == from and no self-approval exists
    /// @dev Regression: inherits the corrected allowance-consumption invariant from transferFrom.
    function test_transferFromWithMemo_revert_selfCaller_insufficientAllowance(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, from, 0, amount));
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies transferFromWithMemo decreases self-allowance by the spent amount when caller == from
    /// @dev Regression: spend-tracking parity with transferFrom on the self-caller path.
    function test_transferFromWithMemo_success_selfCaller_decreasesAllowance(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(from, amount);

        vm.prank(from);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.allowance(from, from), 0, "self-allowance must be consumed");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, from))),
            0,
            "allowances[from][from] slot must reflect the consumption"
        );
        assertEq(token.balanceOf(to), amount, "to must receive the transferred amount");
    }

    // ============================================================
    //        REGRESSION: PRIVILEGED BOOTSTRAP ALLOWANCE (BOP-230 / L-04)
    // ============================================================
    //
    // Mirrors the transferFrom regression: a privileged transferFromWithMemo
    // (factory caller during the bootstrap window) consumes allowance exactly
    // like an ordinary call — both checked and decremented — while only the
    // executor-policy check stays bypassed, matching the Rust precompile. See
    // transferFrom.t.sol for the canonical discussion.

    /// @notice Verifies a privileged transferFromWithMemo reverts InsufficientAllowance when allowance is below the spend
    /// @dev Pins that the allowance check is unconditional — a privileged caller is still
    ///      rejected for insufficient allowance; before BOP-230 the privileged path skipped
    ///      the check entirely. Regression: BOP-230 / L-04.
    function test_transferFromWithMemo_revert_privileged_insufficientAllowance(
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount,
        bytes32 memo
    ) public {
        // Mock-only by necessity. This pins a privileged (factory bootstrap) transferFromWithMemo
        // that consumes a pre-existing third-party allowance (allowance[from][factory], from !=
        // factory). Such an allowance can only be set by `from` calling approve, which requires the
        // token to already exist with the bootstrap window CLOSED, yet the privileged path requires
        // the window OPEN (during which the factory is the only caller). The two states are mutually
        // exclusive in any real sequence, so there is no fork-reachable construction. The mock
        // observes it only by reopening the window via vm.store, which has no live-precompile analog.
        vm.skip(livePrecompiles);
        _assumeValidActor(from);
        _assumeValidActor(to);
        allowanceAmount = bound(allowanceAmount, 0, B20Constants.MAX_SUPPLY_CAP - 1);
        spendAmount = bound(spendAmount, allowanceAmount + 1, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, spendAmount);
        vm.prank(from);
        token.approve(address(factory), allowanceAmount);

        // Reopen the factory bootstrap window so the factory caller is privileged.
        vm.store(address(token), MockB20Storage.initializedSlot(), bytes32(0));

        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IB20.InsufficientAllowance.selector, address(factory), allowanceAmount, spendAmount)
        );
        token.transferFromWithMemo(from, to, spendAmount, memo);
    }

    /// @notice Verifies a privileged transferFromWithMemo decrements allowance by the spent amount
    /// @dev Allowance is consumed during the bootstrap window exactly as outside it, matching
    ///      the Rust precompile. Before BOP-230 the privileged path left the allowance
    ///      untouched. Regression: BOP-230 / L-04.
    function test_transferFromWithMemo_success_privileged_decrementsAllowance(
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount,
        bytes32 memo
    ) public {
        // Mock-only by necessity: see test_transferFromWithMemo_revert_privileged_insufficientAllowance.
        // The privileged path needs a pre-existing allowance[from][factory] that cannot be
        // established inside the atomic bootstrap window, so there is no fork-reachable construction.
        vm.skip(livePrecompiles);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        allowanceAmount = bound(allowanceAmount, 1, B20Constants.MAX_SUPPLY_CAP);
        vm.assume(allowanceAmount != type(uint256).max);
        spendAmount = bound(spendAmount, 0, allowanceAmount);

        _mint(from, spendAmount);
        vm.prank(from);
        token.approve(address(factory), allowanceAmount);

        // Reopen the factory bootstrap window so the factory caller is privileged.
        vm.store(address(token), MockB20Storage.initializedSlot(), bytes32(0));

        vm.prank(address(factory));
        token.transferFromWithMemo(from, to, spendAmount, memo);

        assertEq(
            token.allowance(from, address(factory)),
            allowanceAmount - spendAmount,
            "privileged transferFromWithMemo must decrement allowance by the spent amount"
        );
        assertEq(token.balanceOf(to), spendAmount, "to must receive the spent amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, address(factory)))),
            allowanceAmount - spendAmount,
            "allowances[from][factory] slot must reflect the consumed amount"
        );
    }
}
