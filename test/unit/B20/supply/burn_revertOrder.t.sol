// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `burn` (self-burn).
///
/// @notice For each pair of preconditions `burn` enforces, this contract pins the
///         canonical first-firing revert selector. See `mint_revertOrder.t.sol`
///         for the harness rationale.
///
///         **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(BURN)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(BURN_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. BALANCE (`fromBalance < amount` in `_burnRaw`) → `InsufficientBalance`
contract B20BurnRevertOrderTest is B20Test {
    /// @notice PAUSE beats ROLE.
    /// @dev Pause modifier is listed before the role modifier; fires first.
    function test_burn_revertOrder_pause_beats_role(address caller, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        _pause(IB20.PausableFeature.BURN);
        // Caller has no role AND BURN is paused — pause fires first.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        token.burn(amount);
    }

    /// @notice ROLE beats BALANCE.
    /// @dev `onlyRole` modifier runs before `_burnRaw` is reached; insufficient balance never gets checked.
    function test_burn_revertOrder_role_beats_balance(address caller, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        amount = bound(amount, 1, type(uint128).max);
        // Caller has zero balance and no role — role check fires first (pause not set).

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_ROLE)
        );
        token.burn(amount);
    }

    /// @notice PAUSE beats BALANCE.
    /// @dev `whenNotPaused` modifier on the entrypoint fires before `_burnRaw` is invoked.
    function test_burn_revertOrder_pause_beats_balance(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _grantRole(B20Constants.BURN_ROLE, alice);
        _pause(IB20.PausableFeature.BURN);
        // alice has BURN_ROLE but zero balance AND BURN is paused.

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.BURN));
        token.burn(amount);
    }
}
