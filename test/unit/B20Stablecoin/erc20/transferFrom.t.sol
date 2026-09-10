// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20StablecoinTransferFromTest is B20StablecoinTest {
    /// @notice Verifies a Stablecoin operator remains subject to TRANSFER pause
    /// @dev OPERATOR_ROLE waives allowance only.
    function test_transferFrom_revert_operatorWhenTransferPaused(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _grantOperator();
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin operator remains subject to TRANSFER_EXECUTOR_POLICY
    /// @dev OPERATOR_ROLE waives allowance only.
    function test_transferFrom_revert_operatorExecutorPolicyForbids(address from, address to, uint256 amount) public {
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
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin operator can spend from a holder with zero allowance
    /// @dev Confirms the shared allowance bypass applies to the Stablecoin variant.
    function test_transferFrom_success_operatorSpendsWithoutAllowance(address from, address to, uint256 amount) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        _grantOperator();

        vm.prank(operator);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(to), amount, "operator must move holder balance");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, operator))),
            0,
            "zero stored allowance must remain unchanged"
        );
    }

    /// @notice Verifies a Stablecoin operator does not consume a finite stored allowance
    /// @dev Role authority remains independent from holder-managed allowance state.
    function test_transferFrom_success_operatorPreservesStoredAllowance(
        address from,
        address to,
        uint256 storedAllowance,
        uint256 amount
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        storedAllowance = bound(storedAllowance, 0, type(uint256).max - 1);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        vm.prank(from);
        token.approve(operator, storedAllowance);
        _grantOperator();

        vm.prank(operator);
        token.transferFrom(from, to, amount);

        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, operator))),
            storedAllowance,
            "stored allowance must not be consumed"
        );
    }
}
