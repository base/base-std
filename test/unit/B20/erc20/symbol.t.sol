// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";

contract B20SymbolTest is B20Test {
    /// @notice Verifies symbol returns the value passed to the factory at creation
    /// @dev Constructor-stored value readback
    function test_symbol_success_returnsCreationSymbol() public view {
        // The default _b20Params() helper creates a token with symbol "TST".
        assertEq(token.symbol(), "TST", "symbol must match creation value");
    }

    /// @notice Verifies symbol reflects updates made via updateSymbol
    /// @dev Mutable-metadata readback; canonical setter test lives in updateSymbol.t.sol.
    ///      updateSymbol requires METADATA_ROLE, which is held by no one by default.
    function test_symbol_success_reflectsSetSymbol(string calldata newSymbol) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateSymbol(newSymbol);
        assertEq(token.symbol(), newSymbol, "symbol must reflect updateSymbol");
    }
}
