// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20StablecoinTransferFromWithMemoTest is B20StablecoinTest {
    /// @notice Verifies a Stablecoin operator memo transfer remains subject to executor policy
    /// @dev The memo variant preserves the same policy boundary as transferFrom.
    function test_transferFromWithMemo_revert_operatorExecutorPolicyForbids(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(operator != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _grantOperator();
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_EXECUTOR_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies a Stablecoin operator can spend with a memo and zero allowance
    /// @dev Confirms the shared memo allowance bypass applies to the Stablecoin variant.
    function test_transferFromWithMemo_success_operatorSpendsWithoutAllowance(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        _grantOperator();

        vm.prank(operator);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.balanceOf(to), amount, "operator memo transfer must move holder balance");
    }
}
