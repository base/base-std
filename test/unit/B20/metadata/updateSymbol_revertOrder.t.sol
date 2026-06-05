// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Sequential check-order test for `updateSymbol`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(METADATA_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///
///         Single condition: caller must hold METADATA_ROLE. The test fires the
///         revert, grants the required role, and verifies success.
contract B20UpdateSymbolRevertOrderTest is B20Test {
    function test_updateSymbol_revertOrder(address caller, string calldata newSymbol) public {
        _assumeValidCaller(caller);
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        // 1. ROLE fires (caller lacks METADATA_ROLE).
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        token.updateSymbol(newSymbol);
        _grantRole(B20Constants.METADATA_ROLE, caller);

        // Success — caller now holds METADATA_ROLE.
        vm.prank(caller);
        token.updateSymbol(newSymbol);
    }
}
