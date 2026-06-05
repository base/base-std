// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

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
    /// @dev approve sets future-spend authorization, not movement; no gating.
    ///      Paired slot assertion verifies `allowances[owner][spender]`
    ///      slot reflects the write.
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
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            amount,
            "allowances[owner][spender] slot must reflect the approval"
        );
    }

    /// @notice Verifies approve sets allowance(owner, spender) to amount
    /// @dev Overwrites any prior allowance value (no increment / decrement helpers).
    ///      Paired slot assertion verifies both the baseline write and
    ///      the overwrite land at `allowances[owner][spender]`.
    function test_approve_success_setsAllowance(address owner, address spender, uint256 amount) public {
        _assumeValidActor(owner);
        vm.assume(spender != address(0));

        // Set a non-zero baseline, then overwrite to amount, to prove approve replaces (not adds).
        vm.prank(owner);
        token.approve(spender, 42);
        assertEq(token.allowance(owner, spender), 42, "baseline allowance");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            42,
            "baseline allowance slot must hold 42"
        );

        vm.prank(owner);
        token.approve(spender, amount);
        assertEq(token.allowance(owner, spender), amount, "approve must overwrite");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, spender))),
            amount,
            "allowance slot must reflect the overwrite"
        );
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
