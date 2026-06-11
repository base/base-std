// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Sequential check-order test for `mintWithMemo`.
///
/// @notice `mintWithMemo` carries the same preconditions as `mint`; the memo
///         parameter adds no new revert conditions.
///
///         **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(MINT)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(MINT_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         4. POLICY (`_mint` body) → `PolicyForbids`
///         5. SUPPLY-CAP (`_mint` body) → `SupplyCapExceeded`
///
///         The single test below activates all five violations simultaneously,
///         then fixes them one at a time in canonical order, asserting that the
///         next-priority revert fires at each step.
contract B20MintWithMemoRevertOrderTest is B20Test {
    function test_mintWithMemo_revertOrder(address caller, address to, uint256 amount, bytes32 memo) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        // Activate all five violations simultaneously: MINT paused, caller has no
        // MINT_ROLE, address(0) receiver, receiver policy blocks, supply cap = 0.
        _pause(IB20.PausableFeature.MINT);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        vm.prank(admin);
        token.updateSupplyCap(0);

        // 1. PAUSE fires first (role, zero-receiver, policy, cap also violated).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mintWithMemo(address(0), amount, memo);
        _grantRole(B20Constants.UNPAUSE_ROLE, unpauser);
        vm.prank(unpauser);
        token.unpause(_singleFeature(IB20.PausableFeature.MINT));

        // 2. ROLE fires (pause cleared; no MINT_ROLE, address(0) receiver, policy blocks, cap=0).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mintWithMemo(address(0), amount, memo);
        _grantRole(B20Constants.MINT_ROLE, caller);

        // 3. ZERO-RECEIVER fires (pause+role cleared; address(0) receiver, policy blocks, cap=0).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mintWithMemo(address(0), amount, memo);

        // 4. POLICY fires (all earlier cleared; valid receiver, policy blocks, cap=0).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.mintWithMemo(to, amount, memo);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_ALLOW_ID);

        // 5. CAP fires (all earlier cleared; cap=0, amount>0).
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.SupplyCapExceeded.selector, 0, amount));
        token.mintWithMemo(to, amount, memo);
        vm.prank(admin);
        token.updateSupplyCap(B20Constants.MAX_SUPPLY_CAP);

        // Success — all conditions satisfied.
        vm.prank(caller);
        token.mintWithMemo(to, amount, memo);
    }
}
