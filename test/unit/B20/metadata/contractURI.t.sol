// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20ContractURITest is B20Test {
    /// @notice Verifies contractURI returns the value set at token creation
    /// @dev Constructor-stored value readback
    function test_contractURI_success_returnsCreationURI() public {
        // unimplemented
    }

    /// @notice Verifies contractURI reflects updates made via setContractURI
    /// @dev Mutable-metadata readback; canonical setter test lives in setContractURI.t.sol
    function test_contractURI_success_reflectsSetContractURI(string calldata newURI) public {
        // unimplemented
    }
}
