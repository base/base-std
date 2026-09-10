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
        _grantRole(B20Constants.OPERATOR_ROLE, authorizedSpender);

        vm.prank(authorizedSpender);
        vm.expectRevert(abi.encodeWithSelector(IB20.InsufficientAllowance.selector, authorizedSpender, 0, amount));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin authorized spender remains subject to TRANSFER pause
    /// @dev AUTHORIZED_SPENDER_ROLE waives allowance only.
    function test_transferFrom_revert_authorizedSpenderWhenTransferPaused(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _grantAuthorizedSpender();
        _pause(IB20.PausableFeature.TRANSFER);

        vm.prank(authorizedSpender);
        vm.expectRevert(abi.encodeWithSelector(IB20.ContractPaused.selector, IB20.PausableFeature.TRANSFER));
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin authorized spender remains subject to TRANSFER_EXECUTOR_POLICY
    /// @dev AUTHORIZED_SPENDER_ROLE waives allowance only.
    function test_transferFrom_revert_authorizedSpenderExecutorPolicyForbids(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(authorizedSpender != from);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _grantAuthorizedSpender();
        _setPolicy(B20Constants.TRANSFER_EXECUTOR_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        vm.prank(authorizedSpender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.PolicyForbids.selector,
                B20Constants.TRANSFER_EXECUTOR_POLICY,
                PolicyRegistryConstants.ALWAYS_BLOCK_ID
            )
        );
        token.transferFrom(from, to, amount);
    }

    /// @notice Verifies a Stablecoin authorized spender can spend from a holder with zero allowance
    /// @dev Confirms the shared allowance bypass applies to the Stablecoin variant.
    function test_transferFrom_success_authorizedSpenderSpendsWithoutAllowance(address from, address to, uint256 amount)
        public
    {
        _assumeValidActor(from);
        _assumeValidActor(to);
        vm.assume(from != to);
        amount = bound(amount, 0, B20Constants.MAX_SUPPLY_CAP);

        _mint(from, amount);
        _grantAuthorizedSpender();

        vm.prank(authorizedSpender);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(to), amount, "authorized spender must move holder balance");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, authorizedSpender))),
            0,
            "zero stored allowance must remain unchanged"
        );
    }

    /// @notice Verifies a Stablecoin authorized spender does not consume a finite stored allowance
    /// @dev Role authority remains independent from holder-managed allowance state.
    function test_transferFrom_success_authorizedSpenderPreservesStoredAllowance(
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
        token.approve(authorizedSpender, storedAllowance);
        _grantAuthorizedSpender();

        vm.prank(authorizedSpender);
        token.transferFrom(from, to, amount);

        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(from, authorizedSpender))),
            storedAllowance,
            "stored allowance must not be consumed"
        );
    }
}
