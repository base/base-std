// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20ContractURITest is B20Test {
    /// @notice Verifies contractURI returns the value set at token creation
    /// @dev Constructor-stored value readback. The default _assetParams() helper
    ///      doesn't set a contractURI, so a fresh token's contractURI is the
    ///      empty string.
    function test_contractURI_success_returnsCreationURI() public view {
        assertEq(token.contractURI(), "", "fresh token's contractURI must be the empty string");
    }

    /// @notice Verifies contractURI reflects updates made via updateContractURI
    /// @dev Mutable-metadata readback; canonical setter test lives in updateContractURI.t.sol
    function test_contractURI_success_reflectsSetContractURI(string calldata newURI) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateContractURI(newURI);
        assertEq(token.contractURI(), newURI, "contractURI must reflect updateContractURI");
    }
}
