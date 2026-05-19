// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20NameTest is B20Test {
    /// @notice Verifies name returns the value passed to the factory at creation
    /// @dev Constructor-stored value readback
    function test_name_success_returnsCreationName() public {
        // unimplemented
    }

    /// @notice Verifies name reflects updates made via setName
    /// @dev Mutable-metadata readback; canonical setter test lives in setName.t.sol
    function test_name_success_reflectsSetName(string calldata newName) public {
        // unimplemented
    }
}
