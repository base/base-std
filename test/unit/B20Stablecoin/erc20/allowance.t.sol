// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20StablecoinTest} from "base-std-test/lib/B20StablecoinTest.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20StablecoinAllowanceTest is B20StablecoinTest {
    /// @notice Verifies Stablecoin reports infinite allowance for an operator
    /// @dev Role membership overrides the view without changing the stored allowance.
    function test_allowance_success_operatorReadsAsInfinite(address owner, uint256 storedAllowance) public {
        _assumeValidActor(owner);

        vm.prank(owner);
        token.approve(operator, storedAllowance);
        _grantOperator();

        assertEq(token.allowance(owner, operator), type(uint256).max, "operator allowance must be infinite");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.allowanceSlot(owner, operator))),
            storedAllowance,
            "stored allowance must remain unchanged"
        );
    }
}
