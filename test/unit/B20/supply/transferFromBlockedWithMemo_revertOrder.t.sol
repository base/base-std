// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `transferFromBlockedWithMemo`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(SEIZE)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(TRANSFER_FROM_BLOCKED_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver` (`from` is not zero-checked)
///         4. BLOCKED (`isAuthorized(seizablePolicyId, from) == true`) → `AccountNotBlocked`
///         5. BALANCE (`fromBalance < amount` in `_moveBalance`) → `InsufficientBalance`
contract B20TransferFromBlockedWithMemoRevertOrderTest is B20Test {
    address internal seizer = makeAddr("seizer");

    /// @notice PAUSE beats ROLE.
    function test_transferFromBlockedWithMemo_revertOrder_pause_beats_role(address caller, address from, address to)
        public
    {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        _pause(IB20.PausableFeature.SEIZE);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.transferFromBlockedWithMemo(from, to, 1, bytes32(0));
    }

    /// @notice ROLE beats ZERO-ACTORS (unauthorized caller reverts before the `to == 0` check).
    function test_transferFromBlockedWithMemo_revertOrder_role_beats_zeroActors(address caller, address from) public {
        _assumeValidCaller(caller);
        _assumeValidActor(from);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.TRANSFER_FROM_BLOCKED_ROLE
            )
        );
        token.transferFromBlockedWithMemo(from, address(0), 1, bytes32(0));
    }

    /// @notice ZERO-ACTORS beats BLOCKED (`to == 0` reverts before the seizable check on `from`).
    function test_transferFromBlockedWithMemo_revertOrder_zeroActors_beats_blocked(address from) public {
        _assumeValidActor(from);
        _grantRole(B20Constants.TRANSFER_FROM_BLOCKED_ROLE, seizer);
        // SEIZABLE_POLICY left at ALWAYS_ALLOW → `from` would be "not blocked", but `to == 0` fires first.

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.transferFromBlockedWithMemo(from, address(0), 1, bytes32(0));
    }

    /// @notice BLOCKED beats BALANCE (`from` not blocked and zero balance → AccountNotBlocked wins).
    function test_transferFromBlockedWithMemo_revertOrder_blocked_beats_balance(address from, address to) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        _grantRole(B20Constants.TRANSFER_FROM_BLOCKED_ROLE, seizer);
        // Default SEIZABLE_POLICY is ALWAYS_ALLOW → `from` is NOT blocked; zero balance too.

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccountNotBlocked.selector, from));
        token.transferFromBlockedWithMemo(from, to, 1, bytes32(0));
    }

    /// @notice PAUSE beats BLOCKED.
    function test_transferFromBlockedWithMemo_revertOrder_pause_beats_blocked(address from, address to) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        _grantRole(B20Constants.TRANSFER_FROM_BLOCKED_ROLE, seizer);
        _pause(IB20.PausableFeature.SEIZE);
        // SEIZABLE_POLICY left at ALWAYS_ALLOW → `from` "not blocked", but pause fires first.

        vm.prank(seizer);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.SEIZE));
        token.transferFromBlockedWithMemo(from, to, 1, bytes32(0));
    }
}
