// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";

contract B20SetSymbolTest is B20Test {
    /// @notice Verifies setSymbol reverts when caller lacks METADATA_ROLE
    /// @dev Access control: only METADATA_ROLE holders may rename (separated from
    ///      DEFAULT_ADMIN_ROLE per IB20 spec). Checks AccessControlUnauthorizedAccount.
    function test_setSymbol_revert_unauthorized(address caller, string calldata newSymbol) public {
        _assumeValidCaller(caller);
        vm.assume(!token.hasRole(METADATA_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, METADATA_ROLE)
        );
        token.setSymbol(newSymbol);
    }

    /// @notice Verifies setSymbol updates symbol() to the new value
    /// @dev Read-after-write; canonical symbol readback test lives in symbol.t.sol
    function test_setSymbol_success_updatesSymbol(string calldata newSymbol) public {
        _grantRole(METADATA_ROLE, admin);
        vm.prank(admin);
        token.setSymbol(newSymbol);
        assertEq(token.symbol(), newSymbol, "symbol() must return the new value");
    }

    /// @notice Verifies setSymbol emits SymbolUpdated(updater, newSymbol)
    /// @dev Event integrity; canonical SymbolUpdated emission test
    function test_setSymbol_success_emitsSymbolUpdated(string calldata newSymbol) public {
        _grantRole(METADATA_ROLE, admin);
        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.SymbolUpdated(admin, newSymbol);
        vm.prank(admin);
        token.setSymbol(newSymbol);
    }
}
