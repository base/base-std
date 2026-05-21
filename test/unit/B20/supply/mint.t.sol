// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "test/lib/mocks/MockPolicyRegistry.sol";

contract B20MintTest is B20Test {
    /// @notice Verifies mint reverts when caller lacks MINT_ROLE
    /// @dev Access control: only role-holders can mint; checks AccessControlUnauthorizedAccount.
    ///      Note _mint's check order: InvalidReceiver(0) fires BEFORE the role check, so
    ///      we filter to != 0 to exercise the role-check path specifically. The
    ///      InvalidReceiver path is covered by test_mint_revert_zeroRecipient.
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
        cap = bound(cap, 0, type(uint128).max);
        amount = bound(amount, cap + 1, type(uint256).max - cap);

        vm.prank(admin);
        token.setSupplyCap(cap);

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
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID));
        token.mint(to, amount);
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
    /// @dev Accounting: balanceOf(to) increases by exactly amount
    function test_mint_success_creditsRecipient(address to, uint256 amount) public {
        _assumeValidActor(to);
        uint256 before = token.balanceOf(to);

        _mint(to, amount);
        assertEq(token.balanceOf(to), before + amount, "balance must increase by minted amount");
    }

    /// @notice Verifies mint increases totalSupply by amount
    /// @dev Accounting: totalSupply tracks cumulative minted-burned
    function test_mint_success_increasesTotalSupply(address to, uint256 amount) public {
        _assumeValidActor(to);
        uint256 before = token.totalSupply();

        _mint(to, amount);
        assertEq(token.totalSupply(), before + amount, "totalSupply must increase by minted amount");
    }

    /// @notice Verifies mint emits Transfer(address(0), to, amount)
    /// @dev Event integrity for the mint path; mint represented as transfer from the zero address
    function test_mint_success_emitsTransferFromZero(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(address(0), to, amount);
        vm.prank(minter);
        token.mint(to, amount);
    }
}
