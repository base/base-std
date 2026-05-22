// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

contract B20SecurityBatchBurnTest is B20SecurityTest {
    /// @notice Verifies batchBurn reverts when caller lacks BURN_FROM_ROLE
    /// @dev Access control via `onlyRoleStrict(BURN_FROM_ROLE)`: NOT the inherited `onlyRole`,
    ///      because this path deliberately rejects the factory bootstrap bypass (see contract
    ///      natspec). Non-role-holder caller hits the standard AccessControlUnauthorizedAccount.
    function test_batchBurn_revert_unauthorized(address caller) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != burnFromActor);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, BURN_FROM_ROLE));
        security().batchBurn(_singletonAddresses(alice), _singletonUints(1));
    }

    /// @notice Verifies the factory bootstrap bypass is deliberately NOT honored for batchBurn
    /// @dev `onlyRoleStrict` rejects even calls from the factory during the bootstrap window
    ///      (unlike `onlyRole`, which honors `_isPrivileged()`). Triggered by passing a
    ///      `batchBurn(...)` initCall: the call arrives at the token with `msg.sender == factory`
    ///      and `initialized == false`, but `onlyRoleStrict` requires the factory to actually
    ///      hold `BURN_FROM_ROLE` (which it never does), so the init-call reverts and the
    ///      factory bubbles the inner AccessControlUnauthorizedAccount per IB20Factory.InitCallFailed.
    function test_batchBurn_revert_factoryBootstrapBypassRejected(bytes32 salt) public {
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = abi.encodeWithSelector(
            IB20Security.batchBurn.selector, _singletonAddresses(alice), _singletonUints(uint256(1))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, address(factory), BURN_FROM_ROLE)
        );
        _createSecurity(address(this), salt, _securityParams(), initCalls);
    }

    /// @notice Verifies batchBurn reverts when accounts.length != amounts.length
    /// @dev Length-mismatch guard fires after the role check; checks
    ///      LengthMismatch(accounts.length, amounts.length).
    function test_batchBurn_revert_lengthMismatch() public {
        _grantBurnFrom();
        address[] memory accounts = _singletonAddresses(alice);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;

        vm.prank(burnFromActor);
        vm.expectRevert(abi.encodeWithSelector(IB20Security.LengthMismatch.selector, uint256(1), uint256(2)));
        security().batchBurn(accounts, amounts);
    }

    /// @notice Verifies batchBurn reverts when both arrays are empty
    /// @dev EmptyBatch guard: same rationale as batchMint.
    function test_batchBurn_revert_emptyBatch() public {
        _grantBurnFrom();
        vm.prank(burnFromActor);
        vm.expectRevert(IB20Security.EmptyBatch.selector);
        security().batchBurn(new address[](0), new uint256[](0));
    }

    /// @notice Verifies batchBurn reverts when BURN feature is paused
    /// @dev Pause guard fires AFTER the length / empty checks but BEFORE per-element burn.
    function test_batchBurn_revert_whenBurnPaused(uint256 amount) public {
        _grantBurnFrom();
        _pause(IB20.PausableFeature.BURN);

        vm.prank(burnFromActor);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        security().batchBurn(_singletonAddresses(alice), _singletonUints(amount));
    }

    /// @notice Verifies batchBurn surfaces per-element InsufficientBalance reverts
    /// @dev Per-element invariant: `_burnRaw` reverts InsufficientBalance(account, bal, amount)
    ///      if any element exceeds the account's balance. All-or-nothing atomicity.
    function test_batchBurn_revert_insufficientBalance(uint256 amount) public {
        _grantBurnFrom();
        amount = bound(amount, 1, type(uint128).max);
        // alice holds zero balance; any positive amount triggers the revert on element 0.

        vm.prank(burnFromActor);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientBalance.selector, alice, uint256(0), amount));
        security().batchBurn(_singletonAddresses(alice), _singletonUints(amount));
    }

    /// @notice Verifies batchBurn succeeds with a single account and debits the balance
    /// @dev Single-element happy path; balance and totalSupply both drop by amount.
    function test_batchBurn_success_singleAccount(uint256 amount) public {
        _grantBurnFrom();
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(burnFromActor);
        security().batchBurn(_singletonAddresses(alice), _singletonUints(amount));

        assertEq(token.balanceOf(alice), 0, "balance must be zero after full burn");
        assertEq(token.totalSupply(), supplyBefore - amount, "totalSupply must drop by amount");
    }

    /// @notice Verifies batchBurn succeeds with multiple accounts and debits each individually
    /// @dev Multi-element happy path; iteration order doesn't matter for accounting.
    function test_batchBurn_success_multipleAccounts(uint64 a1, uint64 a2, uint64 a3) public {
        _grantBurnFrom();
        a1 = uint64(bound(uint256(a1), 1, type(uint64).max));
        a2 = uint64(bound(uint256(a2), 1, type(uint64).max));
        a3 = uint64(bound(uint256(a3), 1, type(uint64).max));

        address carol = makeAddr("carol");
        _mint(alice, a1);
        _mint(bob, a2);
        _mint(carol, a3);
        uint256 supplyBefore = token.totalSupply();

        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carol;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = a1;
        amounts[1] = a2;
        amounts[2] = a3;

        vm.prank(burnFromActor);
        security().batchBurn(accounts, amounts);

        assertEq(token.balanceOf(alice), 0, "alice balance must be zero");
        assertEq(token.balanceOf(bob), 0, "bob balance must be zero");
        assertEq(token.balanceOf(carol), 0, "carol balance must be zero");
        assertEq(
            token.totalSupply(),
            supplyBefore - uint256(a1) - uint256(a2) - uint256(a3),
            "totalSupply must drop by the sum of amounts"
        );
    }

    /// @notice Verifies batchBurn emits Transfer(account, address(0), amount) per element
    /// @dev Event integrity: the canonical burn-as-transfer-to-zero signal fires per element,
    ///      in iteration order. (`BurnedBlocked` is NOT emitted — that is reserved for the
    ///      sanctions-style `burnBlocked` path per the IB20Security natspec.)
    function test_batchBurn_success_emitsTransferPerElement() public {
        _grantBurnFrom();
        _mint(alice, 100);
        _mint(bob, 200);

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(alice, address(0), 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(bob, address(0), 200);
        vm.prank(burnFromActor);
        security().batchBurn(accounts, amounts);
    }
}
