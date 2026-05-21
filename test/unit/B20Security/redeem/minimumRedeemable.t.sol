// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

import {MockB20RedeemStorage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SecurityMinimumRedeemableTest is B20SecurityTest {
    /// @notice Verifies minimumRedeemable returns the value seeded at creation
    /// @dev The base setUp creates the token with `minimumRedeemable: 0`; readback must match.
    function test_minimumRedeemable_success_defaultIsZero() public view {
        assertEq(security().minimumRedeemable(), 0, "minimumRedeemable must default to 0");
        assertEq(
            uint256(vm.load(address(token), MockB20RedeemStorage.minimumRedeemableSlot())),
            0,
            "stored slot must be zero before any write"
        );
    }

    /// @notice Verifies minimumRedeemable reads back the value updateMinimumRedeemable wrote
    /// @dev Property: getter returns the last written value verbatim.
    function test_minimumRedeemable_success_returnsStoredValue(uint256 newMinimum) public {
        _updateMinimumRedeemable(newMinimum);
        assertEq(security().minimumRedeemable(), newMinimum, "minimumRedeemable must equal last written value");
    }
}
