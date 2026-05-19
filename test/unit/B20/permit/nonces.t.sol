// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20NoncesTest is B20Test {
    /// @notice Verifies nonces returns zero for any account that has never permitted
    /// @dev Default state across the address space
    function test_nonces_success_zeroByDefault(address account) public {
        // unimplemented
    }

    /// @notice Verifies nonces advances by exactly one per successful permit
    /// @dev Replay protection: monotonic counter; canonical permit test lives in permit.t.sol
    function test_nonces_success_advancesPerPermit() public {
        // unimplemented
    }
}
