// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20SetNameTest is B20Test {
    /// @notice Verifies setName reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only admin may rename; checks AccessControlUnauthorizedAccount
    function test_setName_revert_unauthorized(address caller, string calldata newName) public {
        // unimplemented
    }

    /// @notice Verifies setName updates name() to the new value
    /// @dev Read-after-write; canonical name readback test lives in name.t.sol
    function test_setName_success_updatesName(string calldata newName) public {
        // unimplemented
    }

    /// @notice Verifies setName emits NameUpdated(updater, newName)
    /// @dev Event integrity; canonical NameUpdated emission test
    function test_setName_success_emitsNameUpdated(string calldata newName) public {
        // unimplemented
    }
}
