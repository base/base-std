// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20ApproveTest is B20Test {
    /// @notice Verifies approve reverts for the zero spender address
    /// @dev OZ ERC-6093 invariant; checks InvalidSpender(address(0)) error
    function test_approve_revert_zeroSpender(address owner, uint256 amount) public {
        _assumeValidActor(owner);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
    }

    /// @notice Verifies approve reverts when called by the zero address
    /// @dev Defense-in-depth check fired before the spender guard. Reaching it requires
    ///      pranking address(0) directly (our standard _assumeValidActor filter excludes
    ///      it), so this test explicitly does so.
    function test_approve_revert_zeroApprover(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidApprover.selector, address(0)));
        token.approve(spender, amount);
    }

    /// @notice Verifies approve does NOT consult any pause or policy state
    /// @dev approve sets future-spend authorization, not movement; no gating
    function test_approve_success_succeedsWhilePaused(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        vm.assume(spender != address(0));

        // Pause every transfer-adjacent feature; approve should still succeed.
        _pause(IB20.PausableFeature.TRANSFER);
        _pause(IB20.PausableFeature.MINT);
        _pause(IB20.PausableFeature.BURN);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve must succeed even while paused");
        assertEq(token.allowance(owner, spender), amount, "allowance must be set");
    }

    /// @notice Verifies approve sets allowance(owner, spender) to amount
    /// @dev Overwrites any prior allowance value (no increment / decrement helpers)
    function test_approve_success_setsAllowance(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        vm.assume(spender != address(0));

        // Set a non-zero baseline, then overwrite to amount, to prove approve replaces (not adds).
        vm.prank(owner);
        token.approve(spender, 42);
        assertEq(token.allowance(owner, spender), 42, "baseline allowance");

        vm.prank(owner);
        token.approve(spender, amount);
        assertEq(token.allowance(owner, spender), amount, "approve must overwrite");
    }

    /// @notice Verifies approve emits Approval(owner, spender, amount)
    /// @dev Event integrity; canonical Approval event test for the approve path
    function test_approve_success_emitsApproval(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        vm.assume(spender != address(0));

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Approval(owner, spender, amount);
        vm.prank(owner);
        token.approve(spender, amount);
    }

    /// @notice Verifies approve returns true on success
    /// @dev ERC-20 return-value contract
    function test_approve_success_returnsTrue(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        vm.assume(spender != address(0));

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve must return true");
    }
}
