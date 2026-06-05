// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20NameTest is B20Test {
    /// @notice Verifies name returns the value passed to the factory at creation
    /// @dev Constructor-stored value readback
    function test_name_success_returnsCreationName() public view {
        // The default _assetParams() helper creates a token with name "Asset Test".
        assertEq(token.name(), "Asset Test", "name must match creation value");
    }

    /// @notice Verifies name reflects updates made via updateName
    /// @dev Mutable-metadata readback; canonical setter test lives in updateName.t.sol.
    ///      updateName requires METADATA_ROLE, which is held by no one by default.
    function test_name_success_reflectsSetName(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateName(newName);
        assertEq(token.name(), newName, "name must reflect updateName");
    }
}
