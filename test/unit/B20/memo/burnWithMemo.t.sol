// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20BurnWithMemoTest is B20Test {
    /// @notice Verifies burnWithMemo inherits all burn guards
    /// @dev Reuse-of-guards invariant; concrete guard tests live in burn.t.sol.
    ///      We use BURN_ROLE unauthorized as the representative guard.
    function test_burnWithMemo_revert_inheritsBurnGuards(uint256 amount, bytes32 memo) public {
        // alice has no BURN_ROLE.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, alice, B20Constants.BURN_ROLE)
        );
        token.burnWithMemo(amount, memo);
    }

    /// @notice Verifies burnWithMemo debits caller and decreases totalSupply
    /// @dev Accounting unchanged from burn; the memo does not alter accounting.
    ///      Paired slot assertions confirm balance and totalSupply slots reflect the burn.
    function test_burnWithMemo_success_debitsAndDecreasesSupply(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(burner);
        token.burnWithMemo(amount, memo);

        assertEq(token.balanceOf(burner), 0, "burner fully debited");
        assertEq(token.totalSupply(), supplyBefore - amount, "supply decreased");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.balanceSlot(burner))),
            0,
            "balances[burner] slot must reflect the burn"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.totalSupplySlot())),
            supplyBefore - amount,
            "totalSupply slot must reflect the burn"
        );
    }

    /// @notice Verifies burnWithMemo emits Transfer(caller, address(0), amount) then Memo(memo)
    /// @dev Event ordering: Memo follows Transfer; canonical Memo test for the burn path
    function test_burnWithMemo_success_emitsTransferThenMemo(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(burner, address(0), amount);
        vm.expectEmit(true, true, false, false, address(token));
        emit IB20.Memo(burner, memo);
        vm.prank(burner);
        token.burnWithMemo(amount, memo);
    }
}
