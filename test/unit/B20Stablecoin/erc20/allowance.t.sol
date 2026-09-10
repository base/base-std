// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20StablecoinAllowanceTest is B20StablecoinTest {
    /// @notice Verifies a generic OPERATOR_ROLE grant does not create an infinite Stablecoin allowance
    /// @dev The Asset-only role hash remains inert on the shared allowance path.
    function test_allowance_success_operatorRoleDoesNotAuthorizeSpending(address owner) public {
        _assumeValidActor(owner);
        _grantRole(B20Constants.OPERATOR_ROLE, authorizedSpender);

        assertEq(token.allowance(owner, authorizedSpender), 0, "operator role allowance must remain zero");
    }

    /// @notice Verifies Stablecoin reports infinite allowance for an authorized spender
    /// @dev Role membership overrides the view without changing the stored allowance.
    function test_allowance_success_authorizedSpenderReadsAsInfinite(address owner, uint256 storedAllowance) public {
        _assumeValidActor(owner);

        vm.prank(owner);
        token.approve(authorizedSpender, storedAllowance);
        _grantAuthorizedSpender();

        assertEq(
            token.allowance(owner, authorizedSpender),
            type(uint256).max,
            "authorized spender allowance must be infinite"
        );
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, authorizedSpender))),
            storedAllowance,
            "stored allowance must remain unchanged"
        );
    }
}
