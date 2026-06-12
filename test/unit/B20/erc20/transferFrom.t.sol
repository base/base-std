// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20TransferFromTest is B20Test {
    /// @notice Verifies transferFrom reverts when the TRANSFER feature is paused
    /// @dev Pause guard fires in the inner _transfer, after allowance consumption.
    ///      To reach it we need a non-zero allowance so the consumeAllowance step
    ///      doesn't revert first.
    function test_transferFrom_revert_whenTransferPaused(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from); // skip the consume-allowance bypass when caller == from
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        vm.prank(from);
        token.approve(caller, amount);
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when caller is not authorized under TRANSFER_EXECUTOR_POLICY
    /// @dev Executor-side policy guard fires after allowance consumption and before _transfer.
    function test_transferFrom_revert_executorPolicyForbids(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_EXECUTOR_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when from is not authorized under TRANSFER_SENDER_POLICY
    /// @dev Sender-side policy guard fires inside _transfer.
    function test_transferFrom_revert_senderPolicyForbids(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_SENDER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when to is not authorized under TRANSFER_RECEIVER_POLICY
    /// @dev Receiver-side policy guard fires inside _transfer.
    function test_transferFrom_revert_receiverPolicyForbids(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        vm.prank(from);
        token.approve(caller, amount);
        _setPolicy(B20Constants.TRANSFER_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_RECEIVER_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when caller's allowance is insufficient
    /// @dev Allowance precondition fires first when caller != from; checks InsufficientAllowance
    function test_transferFrom_revert_insufficientAllowance(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, type(uint256).max);
        // No approval set; allowance is 0; any nonzero amount exceeds it.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, caller, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom reverts when from's balance is insufficient
    /// @dev Balance precondition fires inside _transfer, after allowance consumption.
    function test_transferFrom_revert_insufficientBalance(address caller, address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);
        // from has zero balance, but allowance is set high enough to clear the allowance gate.

        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, from, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom debits from balance and credits to balance
    /// @dev Accounting invariant for the transferFrom path.
    ///      Paired slot assertions verify both `balances[from]` and
    ///      `balances[to]` slots reflect the move.
    function test_transferFrom_success_movesBalance(address caller, address from, address to, uint256 amount) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(from), 0, "from must be fully debited");
        assertEq(token.balanceOf(to), amount, "to must be fully credited");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(from))),
            0,
            "balances[from] slot must reflect the full debit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            amount,
            "balances[to] slot must reflect the full credit"
        );
    }

    /// @notice Verifies transferFrom decreases caller allowance by exactly amount
    /// @dev Spend-tracking; non-infinite allowances decrement by the transferred amount.
    ///      Paired slot assertion: `allowances[from][caller]` slot
    ///      reflects the consumed amount.
    function test_transferFrom_success_decreasesAllowance(
        address caller,
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        allowanceAmount = bound(allowanceAmount, 1, B20Constants.MAX_SUPPLY_CAP);
        // Cap below type(uint256).max so we exercise the consume path (not the infinite-allowance bypass).
        vm.assume(allowanceAmount != type(uint256).max);
        // spendAmount includes 0 so the assertion (allowance decreases by spendAmount) is
        // exercised across the full valid input domain, including the no-op zero-spend case.
        spendAmount = bound(spendAmount, 0, allowanceAmount);

        _mint(from, spendAmount);
        vm.prank(from);
        token.approve(caller, allowanceAmount);

        vm.prank(caller);
        token.transferFrom(from, to, spendAmount);

        assertEq(
            token.allowance(from, caller), allowanceAmount - spendAmount, "allowance must decrease by spent amount"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, caller))),
            allowanceAmount - spendAmount,
            "allowances[from][caller] slot must reflect the consumed amount"
        );
    }

    /// @notice Verifies transferFrom leaves an infinite allowance unchanged
    /// @dev Convention: type(uint256).max allowance is treated as unlimited and not decremented.
    ///      Paired slot assertion confirms the slot still holds uint256.max.
    function test_transferFrom_success_infiniteAllowanceUnchanged(
        address caller,
        address from,
        address to,
        uint256 amount
    ) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        vm.assume(from != to);
        // Include amount = 0: the infinite-allowance invariant must hold across the full
        // valid input domain, including the no-op zero-transfer case.
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, type(uint256).max);

        vm.prank(caller);
        token.transferFrom(from, to, amount);

        assertEq(token.allowance(from, caller), type(uint256).max, "infinite allowance must be preserved");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, caller))),
            type(uint256).max,
            "allowances[from][caller] slot must still hold the infinite sentinel"
        );
    }

    /// @notice Verifies transferFrom emits Transfer(from, to, amount)
    /// @dev Event integrity for the transferFrom path; canonical Transfer test lives in transfer.t.sol
    function test_transferFrom_success_emitsTransfer(address caller, address from, address to, uint256 amount) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(from, to, amount);
        vm.prank(caller);
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom returns true on success
    /// @dev ERC-20 return-value contract
    function test_transferFrom_success_returnsTrue(address caller, address from, address to, uint256 amount) public {
        _assumeValidActor(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(caller, amount);

        vm.prank(caller);
        assertTrue(token.transferFrom(from, to, amount), "transferFrom must return true");
    }

    // ============================================================
    //              REGRESSION: SELF-CALLER ALLOWANCE
    // ============================================================
    //
    // transferFrom MUST consume allowance even when msg.sender == from.
    // OZ ERC20 and the Rust precompile both carve no exception for the
    // self-caller case, so the mock must not either. Earlier the mock
    // gated `_consumeAllowance` behind `msg.sender != from`, silently
    // letting an owner-as-caller transfer without burning approval —
    // these tests pin the corrected behavior.

    /// @notice Verifies transferFrom reverts InsufficientAllowance when caller == from and no self-approval exists
    /// @dev Regression: without this, msg.sender == from skipped allowance consumption entirely.
    function test_transferFrom_revert_selfCaller_insufficientAllowance(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);
        // No self-approval; allowance[from][from] is 0.

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, from, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies transferFrom decreases self-allowance by the spent amount when caller == from
    /// @dev Regression: matches OZ / Rust — allowance is spent against `allowances[from][from]`.
    function test_transferFrom_success_selfCaller_decreasesAllowance(
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        allowanceAmount = bound(allowanceAmount, 1, B20Constants.MAX_SUPPLY_CAP);
        vm.assume(allowanceAmount != type(uint256).max);
        spendAmount = bound(spendAmount, 1, allowanceAmount);

        _mint(from, spendAmount);
        vm.prank(from);
        token.approve(from, allowanceAmount);

        vm.prank(from);
        token.transferFrom(from, to, spendAmount);

        assertEq(
            token.allowance(from, from), allowanceAmount - spendAmount, "self-allowance must decrease by spent amount"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, from))),
            allowanceAmount - spendAmount,
            "allowances[from][from] slot must reflect the consumed amount"
        );
        assertEq(token.balanceOf(to), spendAmount, "to must receive the spent amount");
    }

    /// @notice Verifies transferFrom with self-caller skips the executor policy check
    /// @dev Self-caller is not an executor distinct from `from`; sender-policy already
    ///      covers `from` inside _transfer. Executor policy MUST NOT fire — pins the
    ///      one carve-out we intentionally keep around `msg.sender == from`.
    function test_transferFrom_success_selfCaller_skipsExecutorPolicy(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(from, amount);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(from);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(to), amount, "transfer must succeed despite blocked executor policy");
    }

    // ============================================================
    //        REGRESSION: PRIVILEGED BOOTSTRAP ALLOWANCE (BOP-230 / L-04)
    // ============================================================
    //
    // A privileged transferFrom (factory caller during the bootstrap
    // window) consumes allowance exactly like an ordinary transferFrom:
    // the allowance is both CHECKED and DECREMENTED. The Rust precompile
    // carves no `privileged` exception for allowance accounting — only the
    // executor-policy check is bypassed for a privileged caller. Before
    // BOP-230 the Solidity reference skipped the entire allowance block
    // during the window (neither checking nor decrementing); these tests
    // pin the corrected, Rust-aligned behavior.
    //
    // To enter the window: set allowance/balance while still initialized,
    // then reopen the bootstrap window via vm.store on the initialized
    // slot, then call as the factory. The privileged spender is the
    // factory address.

    /// @notice Verifies a privileged transferFrom reverts InsufficientAllowance when allowance is below the spend
    /// @dev Pins that the allowance check is unconditional — a privileged caller is still
    ///      rejected for insufficient allowance; before BOP-230 the privileged path skipped
    ///      the check entirely. Regression: BOP-230 / L-04.
    function test_transferFrom_revert_privileged_insufficientAllowance(
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        // Mock-only by necessity. This pins a privileged (factory bootstrap) transferFrom that
        // consumes a pre-existing third-party allowance (allowance[from][factory], from != factory).
        // Such an allowance can only be set by `from` calling approve, which requires the token to
        // already exist with the bootstrap window CLOSED, yet the privileged path requires the
        // window OPEN (during which the factory is the only caller). The two states are mutually
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
        token.transferFrom(from, to, spendAmount);
    }

    /// @notice Verifies a privileged transferFrom decrements allowance by the spent amount
    /// @dev Allowance is consumed during the bootstrap window exactly as outside it, matching
    ///      the Rust precompile. Before BOP-230 the privileged path left the allowance
    ///      untouched. Regression: BOP-230 / L-04.
    function test_transferFrom_success_privileged_decrementsAllowance(
        address from,
        address to,
        uint256 allowanceAmount,
        uint256 spendAmount
    ) public {
        // Mock-only by necessity: see test_transferFrom_revert_privileged_insufficientAllowance.
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
        token.transferFrom(from, to, spendAmount);

        assertEq(
            token.allowance(from, address(factory)),
            allowanceAmount - spendAmount,
            "privileged transferFrom must decrement allowance by the spent amount"
        );
        assertEq(token.balanceOf(to), spendAmount, "to must receive the spent amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, address(factory)))),
            allowanceAmount - spendAmount,
            "allowances[from][factory] slot must reflect the consumed amount"
        );
    }

    /// @notice Verifies a privileged transferFrom bypasses the executor policy while still consuming allowance
    /// @dev Companion to test_transferFrom_success_privileged_decrementsAllowance (which pins allowance
    ///      accounting): this isolates the executor-policy bypass. With TRANSFER_EXECUTOR_POLICY set to
    ///      ALWAYS_BLOCK a non-privileged transferFrom reverts PolicyForbids; the privileged (factory
    ///      bootstrap) path must succeed and still burn the allowance. Only the executor-policy check
    ///      honors the privileged bypass — the allowance is consumed unconditionally (BOP-230 / L-04).
    function test_transferFrom_success_privileged_skipsExecutorPolicy(address from, address to, uint256 amount) public {
        // Mock-only by necessity: like test_transferFrom_revert_privileged_insufficientAllowance,
        // the privileged path needs a pre-existing allowance[from][factory] (from != factory) that
        // cannot be set inside the atomic bootstrap window (the factory is the only in-window
        // caller). No fork-reachable construction exists; the mock reaches it via vm.store.
        vm.skip(livePrecompiles);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(address(factory), amount);
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // Reopen the factory bootstrap window so the factory caller is privileged.
        vm.store(address(token), MockB20Storage.initializedSlot(), bytes32(0));

        vm.prank(address(factory));
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(to), amount, "privileged transferFrom must succeed despite blocked executor policy");
        assertEq(token.allowance(from, address(factory)), 0, "allowance must still be consumed under privilege");
    }
}
