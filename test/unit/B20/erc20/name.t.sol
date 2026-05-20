// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20NameTest is B20Test {
    /// @notice Verifies name returns the value passed to the factory at creation
    /// @dev Constructor-stored value readback
    function test_name_success_returnsCreationName() public view {
        // The default _b20Params() helper creates a token with name "Test".
        assertEq(token.name(), "Test", "name must match creation value");
    }

    /// @notice Verifies name reflects updates made via setName
    /// @dev Mutable-metadata readback; canonical setter test lives in setName.t.sol.
    ///      setName requires METADATA_ROLE, which is held by no one by default.
    function test_name_success_reflectsSetName(string calldata newName) public {
        _grantRole(METADATA_ROLE, admin);
        vm.prank(admin);
        token.setName(newName);
        assertEq(token.name(), newName, "name must reflect setName");
    }
}
