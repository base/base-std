// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `mint`.
///
/// @notice For each pair of preconditions `mint` enforces, this contract pins the
///         canonical first-firing revert selector. Tests pass in mock mode iff the
///         Solidity reference enforces the canonical order, and they pass in fork
///         mode iff the Rust precompile enforces the same order. Any divergence
///         between the two backends surfaces as a fork-mode-only failure with a
///         clear "selector A vs selector B" diff.
///
///         **Canonical order (Option A — Solidity's defensive-depth order):**
///         1. ROLE (`onlyRole(MINT_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         3. PAUSE (`_isPaused(MINT)`) → `ContractPaused`
///         4. POLICY (`isAuthorized(mintReceiverPolicyId, to)`) → `PolicyForbids`
///         5. SUPPLY-CAP (`totalSupply + amount > supplyCap`) → `SupplyCapExceeded`
///
///         A `mint` call that violates two or more preconditions must always
///         revert with the selector for the earliest-listed violation. The 10
///         tests below enumerate every pair (C(5, 2) = 10).
contract B20MintRevertOrderTest is B20Test {
    // --- Pairs where ROLE wins (ROLE is canonical first) ---

    /// @notice With both ROLE and ZERO-RECEIVER violated, ROLE fires first.
    /// @dev Canonical: the `onlyRole` modifier runs before the `to == 0` body check.
    function test_mint_revertOrder_role_beats_zeroRecipient(address caller, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin); // admin holds DEFAULT_ADMIN_ROLE but not MINT_ROLE on fresh token
        // No MINT_ROLE granted; recipient is address(0).

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mint(address(0), amount);
    }

    /// @notice With both ROLE and PAUSE violated, ROLE fires first.
    /// @dev Canonical: modifier runs before any body check, including the pause guard.
    function test_mint_revertOrder_role_beats_pause(address caller, address to, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        _pause(IB20.PausableFeature.MINT);
        // No MINT_ROLE granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mint(to, amount);
    }

    /// @notice With both ROLE and POLICY violated, ROLE fires first.
    /// @dev Canonical: modifier runs before the receiver-policy check.
    function test_mint_revertOrder_role_beats_policy(address caller, address to, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        // No MINT_ROLE granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mint(to, amount);
    }

    /// @notice With both ROLE and CAP violated, ROLE fires first.
    /// @dev Canonical: modifier runs before the supply-cap arithmetic check.
    function test_mint_revertOrder_role_beats_cap(address caller, address to, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0); // any positive amount overflows the cap.
        // No MINT_ROLE granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mint(to, amount);
    }

    // --- Pairs where ZERO-RECEIVER wins (ROLE satisfied) ---

    /// @notice With ZERO-RECEIVER and PAUSE violated, ZERO-RECEIVER fires first.
    /// @dev Canonical: zero-receiver guard runs before the pause guard inside `_mint`.
    function test_mint_revertOrder_zeroRecipient_beats_pause(uint256 amount) public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mint(address(0), amount);
    }

    /// @notice With ZERO-RECEIVER and POLICY violated, ZERO-RECEIVER fires first.
    /// @dev Canonical: zero-receiver guard runs before the receiver-policy check.
    function test_mint_revertOrder_zeroRecipient_beats_policy(uint256 amount) public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mint(address(0), amount);
    }

    /// @notice With ZERO-RECEIVER and CAP violated, ZERO-RECEIVER fires first.
    /// @dev Canonical: zero-receiver guard runs before the supply-cap arithmetic.
    function test_mint_revertOrder_zeroRecipient_beats_cap(uint256 amount) public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mint(address(0), amount);
    }

    // --- Pairs where PAUSE wins (ROLE + ZERO-RECEIVER satisfied) ---

    /// @notice With PAUSE and POLICY violated, PAUSE fires first.
    /// @dev Canonical: pause guard runs before the receiver-policy check.
    function test_mint_revertOrder_pause_beats_policy(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mint(to, amount);
    }

    /// @notice With PAUSE and CAP violated, PAUSE fires first.
    /// @dev Canonical: pause guard runs before the supply-cap arithmetic.
    function test_mint_revertOrder_pause_beats_cap(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mint(to, amount);
    }

    // --- Pair where POLICY wins (ROLE + ZERO + PAUSE satisfied) ---

    /// @notice With POLICY and CAP violated, POLICY fires first.
    /// @dev Canonical: receiver-policy check runs before the supply-cap arithmetic.
    function test_mint_revertOrder_policy_beats_cap(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0);

        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.mint(to, amount);
    }
}
