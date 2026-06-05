// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20Eip712DomainTest is B20Test {
    /// @notice Verifies eip712Domain returns the documented (name, version, chainId, verifyingContract) shape
    /// @dev Per IB20 spec: name is the live token name (default "Test" from factory),
    ///      version is the constant "1", salt and extensions empty.
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

        assertEq(fields, hex"0f", "fields bitfield (name + version + chainId + verifyingContract)");
        assertEq(name_, token.name(), "name must equal live token name");
        assertEq(version, "1", "version pinned to \"1\"");
        assertEq(chainId, block.chainid, "chainId must equal block.chainid");
        assertEq(verifyingContract, address(token), "verifyingContract must equal token address");
        assertEq(salt, bytes32(0), "salt zero");
        assertEq(extensions.length, 0, "extensions empty");
    }

    /// @notice Verifies eip712Domain.fields bitfield reflects which of the five domain components are populated
    /// @dev ERC-5267 fields byte: bit 0 = name, 1 = version, 2 = chainId, 3 = verifyingContract, 4 = salt.
    ///      IB20 populates name, version, chainId, verifyingContract: 0b00001111 = 0x0f.
    function test_eip712Domain_success_fieldsBitfieldMatchesShape() public view {
        (bytes1 fields,,,,,,) = token.eip712Domain();
        assertEq(fields, hex"0f", "fields must be 0x0f (name + version + chainId + verifyingContract)");
    }

    /// @notice Verifies the name field tracks live token name() after updateName
    /// @dev Read-after-write: a successful updateName must immediately surface through
    ///      eip712Domain's name return so off-chain integrators that re-introspect after
    ///      observing EIP712DomainChanged see the new value.
    function test_eip712Domain_success_nameReflectsLiveValue(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateName(newName);

        (, string memory name_,,,,,) = token.eip712Domain();
        assertEq(name_, newName, "eip712Domain.name must equal post-rename name()");
    }

    /// @notice Verifies the chainId field tracks block.chainid after a fork
    /// @dev Mirrors the DOMAIN_SEPARATOR fork-safety test for the introspection path:
    ///      eip712Domain.chainId must reflect block.chainid live, not a snapshot.
    function test_eip712Domain_success_chainIdReflectsLiveValue(uint256 newChainId) public {
        newChainId = bound(newChainId, 1, type(uint64).max);
        vm.chainId(newChainId);
        (,,, uint256 chainId,,,) = token.eip712Domain();
        assertEq(chainId, newChainId, "eip712Domain.chainId must equal post-fork block.chainid");
    }
}
