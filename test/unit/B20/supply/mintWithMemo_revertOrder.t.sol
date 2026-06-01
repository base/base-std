// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

/// @title Differential check-order tests for `mintWithMemo`.
///
/// @notice `mintWithMemo` carries the same preconditions as `mint`; the memo
///         parameter adds no new revert conditions. This file pins the canonical
///         first-firing selector for every pair, mirroring `mint_revertOrder.t.sol`
///         exactly.
///
///         **Canonical order (Solidity reference):**
///         1. PAUSE (`whenNotPaused(MINT)` modifier) → `ContractPaused`
///         2. ROLE (`onlyRole(MINT_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         3. ZERO-RECEIVER (`to == address(0)`) → `InvalidReceiver`
///         4. POLICY (`_mint` body) → `PolicyForbids`
///         5. SUPPLY-CAP (`_mint` body) → `SupplyCapExceeded`
///
///         C(5, 2) = 10 pairs.
contract B20MintWithMemoRevertOrderTest is B20Test {
    // --- Pairs where PAUSE wins (PAUSE is canonical first) ---

    /// @notice With both PAUSE and ROLE violated, PAUSE fires first.
    function test_mintWithMemo_revertOrder_pause_beats_role(
        address caller,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        _pause(IB20.PausableFeature.MINT);
        // No MINT_ROLE granted AND MINT is paused — pause fires first.

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mintWithMemo(to, amount, memo);
    }

    /// @notice With both PAUSE and ZERO-RECEIVER violated, PAUSE fires first.
    function test_mintWithMemo_revertOrder_pause_beats_zeroRecipient(uint256 amount, bytes32 memo) public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);
        // minter has role; recipient is address(0); MINT is paused — pause fires first.

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mintWithMemo(address(0), amount, memo);
    }

    /// @notice With PAUSE and POLICY violated, PAUSE fires first.
    function test_mintWithMemo_revertOrder_pause_beats_policy(address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mintWithMemo(to, amount, memo);
    }

    /// @notice With PAUSE and CAP violated, PAUSE fires first.
    function test_mintWithMemo_revertOrder_pause_beats_cap(address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mintWithMemo(to, amount, memo);
    }

    // --- Pairs where ROLE wins (PAUSE not violated) ---

    /// @notice With both ROLE and ZERO-RECEIVER violated, ROLE fires first.
    function test_mintWithMemo_revertOrder_role_beats_zeroRecipient(address caller, uint256 amount, bytes32 memo)
        public
    {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        // No MINT_ROLE granted; recipient is address(0); pause not set.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mintWithMemo(address(0), amount, memo);
    }

    /// @notice With both ROLE and POLICY violated, ROLE fires first.
    function test_mintWithMemo_revertOrder_role_beats_policy(
        address caller,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        // No MINT_ROLE granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mintWithMemo(to, amount, memo);
    }

    /// @notice With both ROLE and CAP violated, ROLE fires first.
    function test_mintWithMemo_revertOrder_role_beats_cap(
        address caller,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0);
        // No MINT_ROLE granted.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mintWithMemo(to, amount, memo);
    }

    // --- Pairs where ZERO-RECEIVER wins (PAUSE + ROLE satisfied) ---

    /// @notice With ZERO-RECEIVER and POLICY violated, ZERO-RECEIVER fires first.
    function test_mintWithMemo_revertOrder_zeroRecipient_beats_policy(uint256 amount, bytes32 memo) public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mintWithMemo(address(0), amount, memo);
    }

    /// @notice With ZERO-RECEIVER and CAP violated, ZERO-RECEIVER fires first.
    function test_mintWithMemo_revertOrder_zeroRecipient_beats_cap(uint256 amount, bytes32 memo) public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        amount = bound(amount, 1, type(uint128).max);
        vm.prank(admin);
        token.updateSupplyCap(0);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mintWithMemo(address(0), amount, memo);
    }

    // --- Pair where POLICY wins (PAUSE + ROLE + ZERO-RECEIVER satisfied) ---

    /// @notice With POLICY and CAP violated, POLICY fires first.
    function test_mintWithMemo_revertOrder_policy_beats_cap(address to, uint256 amount, bytes32 memo) public {
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
        token.mintWithMemo(to, amount, memo);
    }
}
