// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecuritySecurityIdentifierTest is B20SecurityTest {
    /// @notice Verifies securityIdentifier returns the empty string for an unset identifier
    /// @dev Default for any unset mapping entry is the empty string; the API contract is that
    ///      unset and explicitly-empty both read back as "".
    function test_securityIdentifier_success_emptyForUnset() public view {
        assertEq(security().securityIdentifier(IDENTIFIER_CUSIP), "", "unset identifier must read as empty string");
        assertEq(security().securityIdentifier(IDENTIFIER_FIGI), "", "unset identifier must read as empty string");
    }

    /// @notice Verifies the ISIN seeded at creation is readable via securityIdentifier
    /// @dev `_securityParams()` seeds `DEFAULT_ISIN` at creation; readback must match.
    function test_securityIdentifier_success_returnsIsinSeededAtCreation() public view {
        assertEq(
            security().securityIdentifier(IDENTIFIER_ISIN), DEFAULT_ISIN, "ISIN must match the value seeded at creation"
        );
    }

    /// @notice Verifies securityIdentifier reads back any value written via updateSecurityIdentifier
    /// @dev Property: setter-then-getter round-trip for arbitrary identifier values.
    function test_securityIdentifier_success_returnsStoredValue(string calldata value) public {
        vm.assume(bytes(value).length > 0);
        _grantOperator();
        vm.prank(operator);
        security().updateSecurityIdentifier(IDENTIFIER_CUSIP, value);
        assertEq(security().securityIdentifier(IDENTIFIER_CUSIP), value, "getter must return the last written value");
    }
}
