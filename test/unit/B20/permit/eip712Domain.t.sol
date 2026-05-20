// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20Eip712DomainTest is B20Test {
    /// @notice Verifies eip712Domain returns the documented (chainId, verifyingContract)-only shape
    /// @dev Per IB20 spec: name and version are intentionally empty; salt and extensions empty
    function test_eip712Domain_success_returnsExpectedFields() public view {
        (
            bytes1 fields,
            string memory name_,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = token.eip712Domain();

        assertEq(fields, hex"0c", "fields bitfield (chainId + verifyingContract only)");
        assertEq(name_, "", "name intentionally empty");
        assertEq(version, "", "version intentionally empty");
        assertEq(chainId, block.chainid, "chainId must equal block.chainid");
        assertEq(verifyingContract, address(token), "verifyingContract must equal token address");
        assertEq(salt, bytes32(0), "salt zero");
        assertEq(extensions.length, 0, "extensions empty");
    }

    /// @notice Verifies eip712Domain.fields bitfield reflects which of the five domain components are populated
    /// @dev ERC-5267 fields byte: bit 0 = name, 1 = version, 2 = chainId, 3 = verifyingContract, 4 = salt.
    ///      Default tokens populate only chainId (bit 2) and verifyingContract (bit 3): 0b00001100 = 0x0c.
    function test_eip712Domain_success_fieldsBitfieldMatchesShape() public view {
        (bytes1 fields,,,,,,) = token.eip712Domain();
        assertEq(fields, hex"0c", "fields must be 0x0c (chainId + verifyingContract)");
    }
}
