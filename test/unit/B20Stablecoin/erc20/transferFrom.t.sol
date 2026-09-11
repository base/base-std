// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";
import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

contract B20StablecoinTransferFromTest is B20StablecoinTest {
    /// @notice Verifies a generic OPERATOR_ROLE grant cannot spend from a Stablecoin holder
    /// @dev The Asset-only role hash remains inert on the shared transferFrom path.
    function test_transferFrom_revert_operatorRoleDoesNotAuthorizeSpending(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 1, type(uint256).max);
        _grantRole(B20Constants.OPERATOR_ROLE, preauthorizedSpender);

        vm.prank(preauthorizedSpender);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, preauthorizedSpender, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin preauthorized spender remains subject to TRANSFER pause
    /// @dev PREAUTHORIZED_SPENDER_ROLE waives allowance only.
    function test_transferFrom_revert_preauthorizedSpenderWhenTransferPaused(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _grantPreauthorizedSpender();
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(preauthorizedSpender);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin preauthorized spender remains subject to TRANSFER_EXECUTOR_POLICY
    /// @dev PREAUTHORIZED_SPENDER_ROLE waives allowance only.
    function test_transferFrom_revert_preauthorizedSpenderExecutorPolicyForbids(
        address from,
        address to,
        uint256 amount
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
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin preauthorized spender can spend from a holder with zero allowance
    /// @dev Confirms the shared allowance bypass applies to the Stablecoin variant.
    function test_transferFrom_success_preauthorizedSpenderSpendsWithoutAllowance(
        address from,
        address to,
        uint256 amount
    ) public {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        _grantPreauthorizedSpender();

        vm.prank(preauthorizedSpender);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(to), amount, "preauthorized spender must move holder balance");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, preauthorizedSpender))),
            0,
            "zero stored allowance must remain unchanged"
        );
    }

    /// @notice Verifies a Stablecoin preauthorized spender does not consume a finite stored allowance
    /// @dev Role authority remains independent from holder-managed allowance state.
    function test_transferFrom_success_preauthorizedSpenderPreservesStoredAllowance(
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
        token.approve(preauthorizedSpender, storedAllowance);
        _grantPreauthorizedSpender();

        vm.prank(preauthorizedSpender);
        token.transferFrom(from, to, amount);

        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, preauthorizedSpender))),
            storedAllowance,
            "stored allowance must not be consumed"
        );
    }
}
