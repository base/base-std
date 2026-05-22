// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20SecurityRedeemWithMemoTest is B20SecurityTest {
    /// @dev Open redemption by default for this test suite. Individual tests that need
    ///      ALWAYS_BLOCK call _setRedeemPolicy(ALWAYS_BLOCK_ID) explicitly.
    function setUp() public override {
        super.setUp();
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_ALLOW_ID);
    }

    /// @notice Verifies redeemWithMemo reverts when REDEEM feature is paused
    /// @dev Pause guard fires first; memo path inherits the same guard as the bare `redeem`.
    function test_redeemWithMemo_revert_whenRedeemPaused(uint256 amount, bytes32 memo) public {
        _pause(IB20.PausableFeature.REDEEM);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.REDEEM));
        security().redeemWithMemo(amount, memo);
    }

    /// @notice Verifies redeemWithMemo reverts when caller fails REDEEM_SENDER_POLICY
    /// @dev Policy guard inherited from `_redeemBurn`; same revert as bare `redeem`.
    function test_redeemWithMemo_revert_senderPolicyForbids(uint256 amount, bytes32 memo) public {
        _setRedeemPolicy(PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, REDEEM_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        security().redeemWithMemo(amount, memo);
    }

    /// @notice Verifies redeemWithMemo reverts when the resulting share count is below the floor
    /// @dev Same BelowMinimumRedeemable path as bare `redeem`; the memo path shares `_redeemBurn`.
    function test_redeemWithMemo_revert_belowMinimum(uint256 amount, uint256 minimum, bytes32 memo) public {
        amount = bound(amount, 1, type(uint128).max);
        minimum = bound(minimum, amount + 1, type(uint256).max);
        _updateMinimumRedeemable(minimum);
        _mint(alice, amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20Security.BelowMinimumRedeemable.selector, amount, minimum));
        security().redeemWithMemo(amount, memo);
    }

    /// @notice Verifies redeemWithMemo accepts the zero memo
    /// @dev `bytes32(0)` is a permitted memo per IB20Security natspec; the call must succeed.
    function test_redeemWithMemo_success_zeroMemoPermitted(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);

        vm.prank(alice);
        security().redeemWithMemo(amount, bytes32(0));
        assertEq(token.balanceOf(alice), 0, "balance must be debited even with zero memo");
    }

    /// @notice Verifies redeemWithMemo emits events in the order Transfer -> Memo -> Redeemed
    /// @dev Critical log-ordering invariant for the memo'd redemption path. Indexers join
    ///      Memo to the surrounding redemption by adjacency, which only holds if the order
    ///      is exactly Transfer (from burn), Memo, Redeemed.
    function test_redeemWithMemo_success_orderingTransferMemoRedeemed(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);

        vm.recordLogs();
        vm.prank(alice);
        security().redeemWithMemo(amount, memo);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 transferAt = _firstLogIndex(logs, IB20.Transfer.selector);
        int256 memoAt = _firstLogIndex(logs, IB20.Memo.selector);
        int256 redeemedAt = _firstLogIndex(logs, IB20Security.Redeemed.selector);
        assertGt(transferAt, -1, "Transfer must be present in the log");
        assertGt(memoAt, -1, "Memo must be present in the log");
        assertGt(redeemedAt, -1, "Redeemed must be present in the log");
        assertLt(transferAt, memoAt, "Transfer must precede Memo");
        assertLt(memoAt, redeemedAt, "Memo must precede Redeemed");
    }

    /// @notice Verifies redeemWithMemo emits the Memo event with the supplied memo
    /// @dev Event-content integrity for the Memo emission. Combined with the ordering test
    ///      above, the redemption emits exactly the {Transfer, Memo, Redeemed} sequence.
    function test_redeemWithMemo_success_emitsMemo(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Memo(alice, memo);
        vm.prank(alice);
        security().redeemWithMemo(amount, memo);
    }
}
