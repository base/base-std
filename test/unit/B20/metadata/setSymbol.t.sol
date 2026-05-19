// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20SetSymbolTest is B20Test {
    /// @notice Verifies setSymbol reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only admin may rename; checks AccessControlUnauthorizedAccount
    function test_setSymbol_revert_unauthorized(address caller, string calldata newSymbol) public {
        // unimplemented
    }

    /// @notice Verifies setSymbol updates symbol() to the new value
    /// @dev Read-after-write; canonical symbol readback test lives in symbol.t.sol
    function test_setSymbol_success_updatesSymbol(string calldata newSymbol) public {
        // unimplemented
    }

    /// @notice Verifies setSymbol emits SymbolUpdated(updater, newSymbol)
    /// @dev Event integrity; canonical SymbolUpdated emission test
    function test_setSymbol_success_emitsSymbolUpdated(string calldata newSymbol) public {
        // unimplemented
    }
}
