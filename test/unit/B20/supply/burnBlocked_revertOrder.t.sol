// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `burnBlocked`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(SEIZE)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(BURN_BLOCKED_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. BLOCKED (`isAuthorized(seizablePolicyId, from) == true` reverts) → `AccountNotBlocked`
///         4. BALANCE (`fromBalance < amount` in `_burnRaw`) → `InsufficientBalance`
///
///         Note on BLOCKED semantics: `burnBlocked` is a clawback function — it
///         only succeeds when `from` is currently NOT authorized by the
///         seizable policy. A test triggers the BLOCKED-precondition
///         violation by setting the policy to `ALWAYS_ALLOW` so every account is
///         authorized, which makes the function revert `AccountNotBlocked`.
contract B20BurnBlockedRevertOrderTest is B20Test {
    // --- Pair where PAUSE wins (PAUSE is canonical first) ---

    /// @notice PAUSE beats ROLE.
    /// @dev Pause modifier is listed before the role modifier; fires first.
    function test_burnBlocked_revertOrder_pause_beats_role(address caller, address from, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != admin);
        _pause(IB20.PausableFeature.SEIZE);
        // No BURN_BLOCKED_ROLE granted AND SEIZE is paused — pause fires first.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.burnBlocked(from, amount);
    }

    // --- Pairs where ROLE wins (PAUSE not violated) ---

    /// @notice ROLE beats BLOCKED.
    function test_burnBlocked_revertOrder_role_beats_blocked(address caller, address from, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != admin);
        // SEIZABLE_ACCOUNT_POLICY left at ALWAYS_ALLOW default → `from` is "not blocked".
        // No BURN_BLOCKED_ROLE granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_BLOCKED_ROLE
            )
        );
        token.burnBlocked(from, amount);
    }

    /// @notice ROLE beats BALANCE.
    function test_burnBlocked_revertOrder_role_beats_balance(address caller, address from, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != admin);
        amount = bound(amount, 1, type(uint128).max);
        // `from` has zero balance, no role granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_BLOCKED_ROLE
            )
        );
        token.burnBlocked(from, amount);
    }

    // --- Pairs where PAUSE wins ---

    /// @notice PAUSE beats BLOCKED.
    function test_burnBlocked_revertOrder_pause_beats_blocked(address from, uint256 amount) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        _pause(IB20.PausableFeature.SEIZE);
        // SEIZABLE_ACCOUNT_POLICY left at ALWAYS_ALLOW → `from` is "not blocked".

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.burnBlocked(from, amount);
    }

    /// @notice PAUSE beats BALANCE.
    function test_burnBlocked_revertOrder_pause_beats_balance(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 1, type(uint128).max);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        _pause(IB20.PausableFeature.SEIZE);
        // Need `from` blocked so BLOCKED would pass; set seizable policy to ALWAYS_BLOCK.
        _setPolicy(B20Constants.SEIZABLE_ACCOUNT_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.burnBlocked(from, amount);
    }

    // --- Pair where BLOCKED wins ---

    /// @notice BLOCKED beats BALANCE.
    /// @dev `from` is not blocked AND has insufficient balance — BLOCKED check fires before `_burnRaw`.
    function test_burnBlocked_revertOrder_blocked_beats_balance(address from, uint256 amount) public {
        _assumeValidActor(from);
        amount = bound(amount, 1, type(uint128).max);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        // Default SEIZABLE_ACCOUNT_POLICY is ALWAYS_ALLOW → `from` is NOT blocked.
        // `from` has zero balance → balance check WOULD fail if BLOCKED didn't fire first.

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotBlocked.selector, from));
        token.burnBlocked(from, amount);
    }
}
