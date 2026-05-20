// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

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
    /// @dev Accounting unchanged from burn; the memo does not alter accounting
    function test_burnWithMemo_success_debitsAndDecreasesSupply(uint256 amount, bytes32 memo) public {
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(burner);
        token.burnWithMemo(amount, memo);

        assertEq(token.balanceOf(burner), 0, "burner fully debited");
        assertEq(token.totalSupply(), supplyBefore - amount, "supply decreased");
    }

    /// @notice Verifies burnWithMemo emits Transfer(caller, address(0), amount) then Memo
    /// @dev Memo is self-contained: carries from, to, amount, memo, and a unique nonce.
    ///      nonce is 0 for the first memo'd operation on a freshly-etched token.
    function test_burnWithMemo_success_emitsTransferThenMemo(uint256 amount, bytes32 memo) public {
        _grantRole(B20Constants.BURN_ROLE, burner);
        _mint(burner, amount);

        vm.expectEmit(true, true, false, true, address(token));
        emit IB20.Transfer(burner, address(0), amount);
        vm.expectEmit(address(token));
        emit IB20.Memo(burner, address(0), amount, memo, 0);
        vm.prank(burner);
        token.burnWithMemo(amount, memo);
    }
}
