// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20MintWithMemoTest is B20Test {
    /// @notice Verifies mintWithMemo inherits all mint guards
    /// @dev Reuse-of-guards invariant; concrete guard tests live in mint.t.sol.
    ///      We use MINT_ROLE unauthorized as the representative guard.
    function test_mintWithMemo_revert_inheritsMintGuards(address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(to);
        // alice has no MINT_ROLE.

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, alice, B20Constants.MINT_ROLE)
        );
        token.mintWithMemo(to, amount, memo);
    }

    /// @notice Verifies mintWithMemo credits the recipient and updates totalSupply
    /// @dev Accounting unchanged from mint; the memo does not alter accounting.
    ///      Paired slot assertions confirm balance and totalSupply slots reflect the mint.
    function test_mintWithMemo_success_creditsAndUpdatesSupply(address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _grantRole(B20Constants.MINT_ROLE, minter);

        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(to);

        vm.prank(minter);
        token.mintWithMemo(to, amount, memo);

        assertEq(token.balanceOf(to), balBefore + amount, "recipient credited");
        assertEq(token.totalSupply(), supplyBefore + amount, "supply increased");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(to))),
            balBefore + amount,
            "balances[to] slot must reflect the mint credit"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            supplyBefore + amount,
            "totalSupply slot must reflect the mint"
        );
    }

    /// @notice Verifies mintWithMemo emits Transfer(address(0), to, amount) then Memo(memo)
    /// @dev Event ordering: Memo follows Transfer; canonical Memo test for the mint path
    function test_mintWithMemo_success_emitsTransferThenMemo(address to, uint256 amount, bytes32 memo) public {
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _grantRole(B20Constants.MINT_ROLE, minter);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(address(0), to, amount);
        vm.expectEmit(true, true, false, false, address(token));
        emit IB20.Memo(minter, memo);
        vm.prank(minter);
        token.mintWithMemo(to, amount, memo);
    }
}
