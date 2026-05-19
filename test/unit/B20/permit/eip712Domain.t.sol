// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20Eip712DomainTest is B20Test {
    /// @notice Verifies eip712Domain returns the documented (chainId, verifyingContract)-only shape
    /// @dev Per IB20 spec: name and version are intentionally empty; salt and extensions empty
    function test_eip712Domain_success_returnsExpectedFields() public {
        // unimplemented
    }

    /// @notice Verifies eip712Domain.fields bitfield reflects which of the five domain components are populated
    /// @dev ERC-5267 fields byte: bits 0..4 correspond to name/version/chainId/verifyingContract/salt
    function test_eip712Domain_success_fieldsBitfieldMatchesShape() public {
        // unimplemented
    }
}
