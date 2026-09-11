// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20StablecoinTransferFromWithMemoTest is B20StablecoinTest {
    /// @notice Verifies a generic OPERATOR_ROLE grant cannot spend with a memo from a Stablecoin holder
    /// @dev The Asset-only role hash remains inert on the shared memo transfer path.
    function test_transferFromWithMemo_revert_operatorRoleDoesNotAuthorizeSpending(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);
        _grantRole(B20Constants.OPERATOR_ROLE, preauthorizedSpender);

        vm.prank(preauthorizedSpender);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, preauthorizedSpender, 0, amount));
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies a Stablecoin preauthorized spender memo transfer remains subject to executor policy
    /// @dev The memo variant preserves the same policy boundary as transferFrom.
    function test_transferFromWithMemo_revert_preauthorizedSpenderExecutorPolicyForbids(
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(preauthorizedSpender != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _grantPreauthorizedSpender();
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(preauthorizedSpender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_EXECUTOR_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFromWithMemo(from, to, amount, memo);
    }

    /// @notice Verifies a Stablecoin preauthorized spender can spend with a memo and zero allowance
    /// @dev Confirms the shared memo allowance bypass applies to the Stablecoin variant.
    function test_transferFromWithMemo_success_preauthorizedSpenderSpendsWithoutAllowance(
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
        _grantPreauthorizedSpender();

        vm.prank(preauthorizedSpender);
        token.transferFromWithMemo(from, to, amount, memo);

        assertEq(token.balanceOf(to), amount, "preauthorized spender memo transfer must move holder balance");
    }
}
