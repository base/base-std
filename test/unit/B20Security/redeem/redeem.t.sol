// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";
import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20SecurityRedeemTest is B20SecurityTest {
    /// @notice Opens REDEEM_SENDER_POLICY for the redemption-path tests in this contract.
    ///         Security tokens default REDEEM_SENDER_POLICY to ALWAYS_BLOCK_ID at creation
    ///         time so admins must explicitly open redemption. Tests in this contract
    ///         exercise the redemption code path itself (balance, minimum, ratio, events,
    ///         ordering), not the policy guard — so we open the policy in setUp to let
    ///         the path under test be the thing being asserted. The one test that pins
    ///         the policy guard (`test_redeem_revert_senderPolicyForbids`) explicitly
    ///         sets ALWAYS_BLOCK_ID itself.
    function setUp() public virtual override {
        super.setUp();
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_ALLOW_ID);
    }

    /// @notice Verifies redeem reverts when REDEEM feature is paused
    /// @dev Pause guard fires first in execution order; checks ContractPaused(REDEEM) error.
    function test_redeem_revert_whenRedeemPaused(uint256 amount) public {
        _pause(IB20.PausableFeature.REDEEM);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.REDEEM));
        security().redeem(amount);
    }

    /// @notice Verifies redeem reverts when caller fails REDEEM_SENDER_POLICY
    /// @dev Policy guard fires after pause check; sets REDEEM_SENDER_POLICY to ALWAYS_BLOCK
    ///      and checks PolicyForbids(REDEEM_SENDER_POLICY, ALWAYS_BLOCK_ID).
    function test_redeem_revert_senderPolicyForbids(uint256 amount) public {
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, REDEEM_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        security().redeem(amount);
    }

    /// @notice Verifies redeem reverts when the caller passes amount == 0
    /// @dev Explicit zero-amount guard mirroring the Rust precompile. Fires AFTER pause/policy
    ///      but BEFORE the shares math, so the error is IB20.InvalidAmount() (not the
    ///      BelowMinimumRedeemable that would otherwise catch zero shares downstream). The
    ///      distinction matters for integrators that distinguish "amount must be non-zero"
    ///      from "amount too small to clear the minimum-shares floor".
    function test_redeem_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IB20.InvalidAmount.selector);
        security().redeem(0);
    }

    /// @notice Verifies redeem reverts when the resulting share count is below the configured floor
    /// @dev Error message reports the computed shares and the configured minimum. Test sets the
    ///      floor above the requested share count and checks BelowMinimumRedeemable(shares, minimum).
    function test_redeem_revert_belowMinimum(uint256 amount, uint256 minimum) public {
        // Use WAD ratio (default) so shares == amount.
        amount = bound(amount, 1, type(uint128).max);
        minimum = bound(minimum, amount + 1, type(uint256).max);
        _updateMinimumRedeemable(minimum);
        _mint(alice, amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20Security.BelowMinimumRedeemable.selector, amount, minimum));
        security().redeem(amount);
    }

    /// @notice Verifies redeem reverts when share count rounds down to zero even with minimum == 0
    /// @dev Always-reject-zero invariant: a holder cannot burn token dust that resolves to zero
    ///      shares under the active ratio, regardless of how `minimumRedeemable` is configured.
    ///      Set ratio so that shares = amount * ratio / WAD rounds to 0 for `amount = 1`.
    function test_redeem_revert_zeroShares_alwaysRejected(uint256 amount) public {
        // Pick a ratio strictly less than WAD so that small amounts round to 0 shares.
        // With ratio = 1 and amount in [1, WAD-1], shares = amount * 1 / WAD = 0.
        amount = bound(amount, 1, security().WAD_PRECISION() - 1);
        _updateShareRatio(1);
        _mint(alice, amount);
        // Leave minimumRedeemable at 0; the zero-share path must still reject.
        assertEq(security().minimumRedeemable(), 0, "minimumRedeemable must remain 0 for this test");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20Security.BelowMinimumRedeemable.selector, 0, 0));
        security().redeem(amount);
    }

    /// @notice Verifies redeem reverts when caller has insufficient balance
    /// @dev Balance precondition (checked inside `_burnRaw` after the redeem-side guards pass).
    ///      Checks InsufficientBalance(caller, balance, amount).
    function test_redeem_revert_insufficientBalance(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        // alice holds zero balance and the default WAD ratio + zero floor lets the amount through
        // to the burn path.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, alice, 0, amount));
        security().redeem(amount);
    }

    /// @notice Verifies redeem debits the caller's balance and decreases totalSupply by amount
    /// @dev Accounting: balanceOf(caller) drops by exactly amount, totalSupply drops by exactly
    ///      amount. Paired slot assertions confirm the storage writes land at the canonical slots.
    function test_redeem_success_debitsCallerAndSupply(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        security().redeem(amount);

        assertEq(token.balanceOf(alice), 0, "caller balance must be zero after full redeem");
        assertEq(token.totalSupply(), supplyBefore - amount, "totalSupply must decrease by redeemed amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(alice))),
            0,
            "balances[alice] slot must reflect the burn"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            supplyBefore - amount,
            "totalSupply slot must reflect the burn"
        );
    }

    /// @notice Verifies redeem emits Transfer(caller, address(0), amount) for the burn leg
    /// @dev Per IB20Security natspec, redeem emits `Transfer` then `Redeemed`. This test pins
    ///      the Transfer event (the canonical burn-as-transfer-to-zero signal); the Redeemed
    ///      event is tested separately.
    function test_redeem_success_emitsTransferToZero(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(alice, address(0), amount);
        vm.prank(alice);
        security().redeem(amount);
    }

    /// @notice Verifies redeem emits Redeemed(caller, amount, sharesToTokensRatio)
    /// @dev Event integrity: the Redeemed event's `ratio` field must equal the ratio that
    ///      was actually used for the share-amount math (so off-chain consumers can recompute
    ///      shares deterministically from the event alone).
    function test_redeem_success_emitsRedeemed(uint256 amount, uint256 ratio) public {
        amount = bound(amount, 1, type(uint64).max);
        ratio = bound(ratio, security().WAD_PRECISION(), type(uint128).max);
        _updateShareRatio(ratio);
        _mint(alice, amount);

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20Security.Redeemed(alice, amount, ratio);
        vm.prank(alice);
        security().redeem(amount);
    }

    /// @notice Verifies redeem emits Transfer strictly before Redeemed
    /// @dev Log-ordering invariant: the burn leg's Transfer event lands in the log before
    ///      the Redeemed event, matching the spec's "burn, then redeem" semantics. Critical
    ///      for indexers that join the two events.
    function test_redeem_success_orderingTransferBeforeRedeemed(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);

        vm.recordLogs();
        vm.prank(alice);
        security().redeem(amount);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 transferAt = _firstLogIndex(logs, IB20.Transfer.selector);
        int256 redeemedAt = _firstLogIndex(logs, IB20Security.Redeemed.selector);
        assertGt(transferAt, -1, "Transfer must be present in the log");
        assertGt(redeemedAt, -1, "Redeemed must be present in the log");
        assertLt(transferAt, redeemedAt, "Transfer must precede Redeemed");
    }
}
