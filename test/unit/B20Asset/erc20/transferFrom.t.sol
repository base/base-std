// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetTransferFromTest is B20AssetTest {
    /// @notice Verifies OPERATOR_ROLE cannot spend from a holder without allowance
    /// @dev Asset operations and holder-spending authority use separate roles.
    function test_transferFrom_revert_operatorRoleDoesNotAuthorizeSpending(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);
        _grantOperator();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, operator, 0, amount));
        token.transferFrom(from, to, amount);
    }
}
