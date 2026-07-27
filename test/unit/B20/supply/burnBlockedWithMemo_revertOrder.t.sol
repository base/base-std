// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `burnBlockedWithMemo`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(SEIZE)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(BURN_BLOCKED_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. BLOCKED (`isAuthorized(seizablePolicyId, from) == true`) → `AccountNotBlocked`
///         4. BALANCE (`fromBalance < amount` in `_burnRaw`) → `InsufficientBalance`
contract B20BurnBlockedWithMemoRevertOrderTest is B20Test {
    /// @notice PAUSE beats ROLE.
    function test_burnBlockedWithMemo_revertOrder_pause_beats_role(address caller, address from) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != admin);
        _pause(IB20.PausableFeature.SEIZE);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.burnBlockedWithMemo(from, 1, bytes32(0));
    }

    /// @notice ROLE beats BLOCKED.
    function test_burnBlockedWithMemo_revertOrder_role_beats_blocked(address caller, address from) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != admin);
        // SEIZABLE_POLICY left at ALWAYS_ALLOW → `from` is "not blocked". No role granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.BURN_BLOCKED_ROLE
            )
        );
        token.burnBlockedWithMemo(from, 1, bytes32(0));
    }

    /// @notice PAUSE beats BLOCKED.
    function test_burnBlockedWithMemo_revertOrder_pause_beats_blocked(address from) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        _pause(IB20.PausableFeature.SEIZE);
        // SEIZABLE_POLICY left at ALWAYS_ALLOW → `from` "not blocked", but pause fires first.

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.burnBlockedWithMemo(from, 1, bytes32(0));
    }

    /// @notice BLOCKED beats BALANCE.
    function test_burnBlockedWithMemo_revertOrder_blocked_beats_balance(address from) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.BURN_BLOCKED_ROLE, burnBlocker);
        // Default SEIZABLE_POLICY is ALWAYS_ALLOW → `from` NOT blocked; zero balance too.

        vm.prank(burnBlocker);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotBlocked.selector, from));
        token.burnBlockedWithMemo(from, 1, bytes32(0));
    }
}
