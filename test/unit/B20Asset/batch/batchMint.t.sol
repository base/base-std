// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20Constants} from "base-std/lib/B20Constants.sol";
import {MockPolicyRegistry, PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20AssetBatchMintTest is B20AssetTest {
    /// @notice Verifies batchMint reverts when recipients.length != amounts.length
    /// @dev Length-mismatch guard fires in batchMint's body, after the entrypoint
    ///      modifiers (PAUSE + MINT_ROLE) and before the empty-batch guard.
    ///      Caller is granted MINT_ROLE so the role modifier passes and the body
    ///      reaches the length check.
    function test_batchMint_revert_lengthMismatch() public {
        _grantRole(B20Constants.MINT_ROLE, minter);

        address[] memory recipients = _singletonAddresses(alice);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20Asset.LengthMismatch.selector, uint256(1), uint256(2)));
        asset().batchMint(recipients, amounts);
    }

    /// @notice Verifies batchMint reverts when both arrays are empty
    /// @dev EmptyBatch guard fires in batchMint's body, after PAUSE + MINT_ROLE
    ///      modifiers. Caller is granted MINT_ROLE so the role modifier passes.
    function test_batchMint_revert_emptyBatch() public {
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.prank(minter);
        vm.expectRevert(IB20Asset.EmptyBatch.selector);
        asset().batchMint(new address[](0), new uint256[](0));
    }

    /// @notice Verifies batchMint reverts when caller lacks MINT_ROLE
    /// @dev `onlyRole(MINT_ROLE)` is now an entrypoint modifier on batchMint
    ///      itself (was per-element via `_mint` before the pause→role→input
    ///      hoist). Any non-minter caller is rejected before the body runs.
    function test_batchMint_revert_unauthorized(address caller, address to, uint256 amount) public {
        _assumeValidCaller(caller);
        _assumeValidActor(to);
        vm.assume(caller != admin);
        vm.assume(caller != minter);
        vm.assume(!token.hasRole(B20Constants.MINT_ROLE, caller));

        address[] memory recipients = _singletonAddresses(to);
        uint256[] memory amounts = _singletonUints(amount);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.MINT_ROLE)
        );
        asset().batchMint(recipients, amounts);
    }

    /// @notice Verifies batchMint surfaces _mint's pause revert when MINT is paused
    /// @dev Pause guard inherited from per-element `_mint`.
    function test_batchMint_revert_whenMintPaused(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _pause(IB20.PausableFeature.MINT);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.MINT));
        asset().batchMint(_singletonAddresses(to), _singletonUints(amount));
    }

    /// @notice Verifies batchMint surfaces _mint's policy revert when MINT_RECEIVER_POLICY forbids
    /// @dev Policy guard applied per recipient by `_mint`; setting ALWAYS_BLOCK rejects any
    ///      recipient.
    function test_batchMint_revert_receiverPolicyForbids(address to, uint256 amount) public {
        _assumeValidActor(to);
        _grantRole(B20Constants.MINT_ROLE, minter);
        _setPolicy(B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector, B20Constants.MINT_RECEIVER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        asset().batchMint(_singletonAddresses(to), _singletonUints(amount));
    }

    /// @notice Verifies batchMint surfaces _mint's supply-cap revert when accumulated mints exceed cap
    /// @dev Cap-accumulation invariant: the cap is checked per recipient against the
    ///      running total, so a batch can overshoot mid-iteration even if no single element does.
    ///      Two recipients each getting `cap` would fit individually but not together.
    function test_batchMint_revert_supplyCapExceededAcrossBatch(address recipientA, address recipientB) public {
        _assumeValidActor(recipientA);
        _assumeValidActor(recipientB);
        vm.assume(recipientA != recipientB);

        vm.prank(admin);
        token.updateSupplyCap(100);
        _grantRole(B20Constants.MINT_ROLE, minter);

        address[] memory recipients = new address[](2);
        recipients[0] = recipientA;
        recipients[1] = recipientB;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 60;
        amounts[1] = 60;

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.SupplyCapExceeded.selector, uint256(100), uint256(120)));
        asset().batchMint(recipients, amounts);
    }

    /// @notice Verifies batchMint reverts when any recipient is the zero address, mid-batch
    /// @dev Per-element zero-receiver guard fires inside the loop (after PAUSE + MINT_ROLE +
    ///      length/empty guards). A zero in a non-first slot proves the check is per-element, and
    ///      the all-or-nothing contract means the earlier valid element's mint is unwound too:
    ///      total supply stays zero after the revert.
    function test_batchMint_revert_zeroRecipient(address validRecipient, uint256 a1, uint256 a2) public {
        _assumeValidActor(validRecipient);
        a1 = bound(a1, 0, type(uint128).max);
        a2 = bound(a2, 0, type(uint128).max);
        _grantRole(B20Constants.MINT_ROLE, minter);

        address[] memory recipients = new address[](2);
        recipients[0] = validRecipient;
        recipients[1] = address(0);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a1;
        amounts[1] = a2;

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidReceiver.selector, address(0)));
        asset().batchMint(recipients, amounts);

        assertEq(token.totalSupply(), 0, "all-or-nothing: earlier element's mint must unwind");
    }

    /// @notice Verifies batchMint succeeds with a single recipient and credits the balance
    /// @dev Single-element happy path; total supply and recipient balance both move by amount.
    function test_batchMint_success_singleRecipient(address to, uint256 amount) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, type(uint128).max);
        _grantRole(B20Constants.MINT_ROLE, minter);

        uint256 supplyBefore = token.totalSupply();
        uint256 balanceBefore = token.balanceOf(to);

        vm.prank(minter);
        asset().batchMint(_singletonAddresses(to), _singletonUints(amount));

        assertEq(token.balanceOf(to), balanceBefore + amount, "balance must increase by amount");
        assertEq(token.totalSupply(), supplyBefore + amount, "totalSupply must increase by amount");
    }

    /// @notice Verifies batchMint succeeds with multiple recipients and credits each individually
    /// @dev Multi-element happy path; iteration ordering doesn't matter for accounting but does
    ///      matter for the supply-cap path. Tests three distinct recipients.
    function test_batchMint_success_multipleRecipients(uint64 a1, uint64 a2, uint64 a3) public {
        _grantRole(B20Constants.MINT_ROLE, minter);

        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = makeAddr("carol");
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = a1;
        amounts[1] = a2;
        amounts[2] = a3;

        uint256 supplyBefore = token.totalSupply();

        vm.prank(minter);
        asset().batchMint(recipients, amounts);

        assertEq(token.balanceOf(recipients[0]), amounts[0], "recipient[0] balance must equal amounts[0]");
        assertEq(token.balanceOf(recipients[1]), amounts[1], "recipient[1] balance must equal amounts[1]");
        assertEq(token.balanceOf(recipients[2]), amounts[2], "recipient[2] balance must equal amounts[2]");
        assertEq(
            token.totalSupply(),
            supplyBefore + uint256(amounts[0]) + uint256(amounts[1]) + uint256(amounts[2]),
            "totalSupply must increase by the sum of amounts"
        );
    }

    /// @notice Verifies batchMint emits Transfer(address(0), recipients[i], amounts[i]) per element
    /// @dev Event integrity for the per-element burn-as-mint signal. Records logs and asserts
    ///      the count and content match the batch.
    function test_batchMint_success_emitsTransferPerElement() public {
        _grantRole(B20Constants.MINT_ROLE, minter);
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(address(0), alice, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(address(0), bob, 200);
        vm.prank(minter);
        asset().batchMint(recipients, amounts);
    }
}
