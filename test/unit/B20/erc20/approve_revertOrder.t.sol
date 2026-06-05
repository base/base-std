// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `approve`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ZERO-APPROVER (`msg.sender == address(0)`) → `InvalidApprover`
///         2. ZERO-SPENDER (`spender == address(0)`) → `InvalidSpender`
///
///         C(2, 2) = 1 pair. ZERO-APPROVER requires pranking `address(0)`.
contract B20ApproveRevertOrderTest is B20Test {
    /// @notice ZERO-APPROVER beats ZERO-SPENDER.
    function test_approve_revertOrder_zeroApprover_beats_zeroSpender(uint256 amount) public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidApprover.selector, address(0)));
        token.approve(address(0), amount);
    }
}
