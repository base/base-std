// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

/// @title Differential check-order tests for `updateSecurityIdentifier`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. ROLE (`onlyRole(SECURITY_OPERATOR_ROLE)` modifier) → `AccessControlUnauthorizedAccount`
///         2. INVALID-IDENTIFIER-TYPE (`bytes(identifierType).length == 0`) → `InvalidIdentifierType`
///
///         C(2, 2) = 1 pair.
contract B20SecurityUpdateSecurityIdentifierRevertOrderTest is B20SecurityTest {
    /// @notice ROLE beats INVALID-IDENTIFIER-TYPE.
    /// @dev Caller lacks SECURITY_OPERATOR_ROLE AND the identifierType is empty.
    ///      Role modifier fires before the body's empty-type check.
    function test_updateSecurityIdentifier_revertOrder_role_beats_invalidIdentifierType(
        address caller,
        string calldata value
    ) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);
        vm.assume(caller != operator);
        bytes32 role = security().SECURITY_OPERATOR_ROLE();

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, role));
        security().updateSecurityIdentifier("", value); // empty type triggers InvalidIdentifierType
    }
}
