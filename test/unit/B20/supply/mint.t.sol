// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20MintTest is B20Test {
    /// @notice Verifies mint reverts when caller lacks MINT_ROLE
    /// @dev Access control: only role-holders can mint; checks AccessControlUnauthorizedAccount.
    ///      The `onlyRole(MINT_ROLE)` modifier on `_mint` runs before any in-body input
    ///      validation, so the role-check path fires regardless of `to`. The
    ///      InvalidReceiver path is covered by test_mint_revert_zeroRecipient. The
    ///      `to != 0` filter is kept for clarity (it documents which path each
    ///      test exercises) but is no longer load-bearing.
    function test_mint_revert_unauthorized(address caller, address to, uint256 amount) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(to != address(0));
        // No MINT_ROLE granted to caller.

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        token.mint(to, amount);
    }

    /// @notice Verifies mint reverts when MINT feature is paused
    /// @dev Pause guard; checks ContractPaused(MINT) error
    function test_mint_revert_whenMintPaused(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        token.mint(to, amount);
    }

    /// @notice Verifies mint reverts when totalSupply + amount > supplyCap
    /// @dev Supply-cap precondition; checks SupplyCapExceeded(cap, attempted) error.
    ///      We set cap low and request more than it allows.
    function test_mint_revert_supplyCapExceeded(address to, uint256 cap, uint256 amount) public {
        _assumeValidActor(to);
        cap = bound(cap, 0, B20Constants.MAX_SUPPLY_CAP);
        amount = bound(amount, cap + 1, type(uint256).max - cap);

        vm.prank(admin);
        token.updateSupplyCap(cap);

        _grantRole(B20Constants.MINT_ROLE, minter);
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.SupplyCapExceeded.selector, cap, amount));
        token.mint(to, amount);
    }

    /// @notice Verifies mint reverts when recipient fails the MINT_RECEIVER_POLICY policy
    /// @dev Policy guard for issuance; checks PolicyForbids(MINT_RECEIVER_POLICY, policyId)
    function test_mint_revert_receiverPolicyForbids(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.mint(to, amount);
    }

    /// @notice Verifies MINT_RECEIVER_POLICY is enforced even for a privileged (factory bootstrap) mint
    /// @dev Mint-side counterpart to the transfer privileged-bypass tests (BOP-332): the bootstrap window
    ///      bypasses the transfer-side policies but ALWAYS enforces MINT_RECEIVER_POLICY, so new supply is
    ///      never issued to a policy-denied recipient even at creation. Privilege is reached through a
    ///      genuine bootstrap: the token is created with initCalls that (1) set the mint-receiver policy to
    ///      ALWAYS_BLOCK, then (2) mint to the blocked recipient. A privileged mint that bypassed the policy
    ///      would succeed; instead the init-call mint reverts PolicyForbids, which the factory bubbles out of
    ///      createB20 — proving the asymmetry. This drives the real factory-as-caller path with no vm.store
    ///      cheat, so it runs identically against the live precompile under LIVE_PRECOMPILES.
    function test_mint_revert_privilegedStillEnforcesReceiverPolicy(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 1, B20Constants.MAX_SUPPLY_CAP);

        bytes32 salt = keccak256("privileged-mint-receiver-enforced");
        // The fuzzed recipient must not collide with the to-be-created token's own address.
        vm.assume(to != factory.getB20Address(IB20Factory.B20Variant.ASSET, alice, salt));

        bytes[] memory initCalls = new bytes[](2);
        initCalls[0] = abi.encodeWithSelector(
            IB20.updatePolicy.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
        );
        initCalls[1] = abi.encodeWithSelector(IB20.mint.selector, to, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        _createAsset(alice, salt, _assetParams(), initCalls);
    }

    /// @notice Verifies mint reverts for the zero recipient address
    /// @dev OZ ERC-6093 invariant; checks InvalidReceiver(address(0)) error
    function test_mint_revert_zeroRecipient(uint256 amount) public {
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        token.mint(address(0), amount);
    }

    /// @notice Verifies mint credits the recipient balance by amount
    /// @dev Accounting: balanceOf(to) increases by exactly amount.
    ///      Paired slot assertion verifies `balances[to]` slot reflects the credit.
    function test_mint_success_creditsRecipient(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        uint256 before = token.balanceOf(to);

        _mint(to, amount);
        assertEq(token.balanceOf(to), before + amount, "balance must increase by minted amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            before + amount,
            "balances[to] slot must reflect the mint credit"
        );
    }

    /// @notice Verifies mint increases totalSupply by amount
    /// @dev Accounting: totalSupply tracks cumulative minted-burned.
    ///      Paired slot assertion verifies `totalSupply` slot reflects the increase.
    function test_mint_success_increasesTotalSupply(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        uint256 before = token.totalSupply();

        _mint(to, amount);
        assertEq(token.totalSupply(), before + amount, "totalSupply must increase by minted amount");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            before + amount,
            "totalSupply slot must reflect the mint"
        );
    }

    /// @notice Verifies mint emits Transfer(address(0), to, amount)
    /// @dev Event integrity for the mint path; mint represented as transfer from the zero address
    function test_mint_success_emitsTransferFromZero(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(address(0), to, amount);
        vm.prank(minter);
        token.mint(to, amount);
    }

    /// @notice Verifies mint succeeds when totalSupply + amount equals supplyCap exactly
    /// @dev Boundary companion to test_mint_revert_supplyCapExceeded (which only exercises
    ///      cap + 1). The `> supplyCap` guard must admit the exact-cap case; minting to the cap
    ///      leaves totalSupply == cap.
    function test_mint_success_atSupplyCapBoundary(address to, uint256 cap) public {
        _assumeValidActor(to);
        cap = bound(cap, 1, B20Constants.MAX_SUPPLY_CAP);

        vm.prank(admin);
        token.updateSupplyCap(cap);

        _mint(to, cap);

        assertEq(token.totalSupply(), cap, "totalSupply must reach exactly the cap");
        assertEq(token.balanceOf(to), cap, "recipient must hold exactly the cap");
    }

    /// @notice Verifies sequential mints to the same recipient accumulate additively
    /// @dev Pins that mint is additive rather than last-write-wins: two mints credit the running
    ///      balance and totalSupply by the sum of both amounts.
    function test_mint_success_accumulatesAcrossCalls(address to, uint256 first, uint256 second) public {
        _assumeValidActor(to);
        // Cumulative supply must stay within the uint128.max cap, so the two
        // amounts together cannot exceed the ceiling.
        first = bound(first, 0, B20Constants.MAX_SUPPLY_CAP);
        second = bound(second, 0, B20Constants.MAX_SUPPLY_CAP - first);

        _mint(to, first);
        _mint(to, second);

        assertEq(token.balanceOf(to), first + second, "balance must equal the sum of both mints");
        assertEq(token.totalSupply(), first + second, "totalSupply must equal the sum of both mints");
    }
}
