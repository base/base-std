// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20SetContractURITest is B20Test {
    /// @notice Verifies setContractURI reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only admin may update the URI; checks AccessControlUnauthorizedAccount
    function test_setContractURI_revert_unauthorized(address caller, string calldata newURI) public {
        // unimplemented
    }

    /// @notice Verifies setContractURI updates contractURI() to the new value
    /// @dev Read-after-write; canonical contractURI readback test lives in contractURI.t.sol
    function test_setContractURI_success_updatesURI(string calldata newURI) public {
        // unimplemented
    }

    /// @notice Verifies setContractURI emits ContractURIUpdated()
    /// @dev ERC-7572 convention: the event is argument-free; integrators refetch via contractURI()
    function test_setContractURI_success_emitsContractURIUpdated(string calldata newURI) public {
        // unimplemented
    }
}
