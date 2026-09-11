// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

contract B20AssetAllowanceTest is B20AssetTest {
    /// @notice Verifies OPERATOR_ROLE does not grant an infinite allowance
    /// @dev Asset operations and holder-spending authority use separate roles.
    function test_allowance_success_operatorRoleDoesNotAuthorizeSpending(address owner) public {
        _assumeValidActor(owner);
        _grantOperator();

        assertEq(token.allowance(owner, operator), 0, "Asset operator allowance must remain zero");
    }
}
