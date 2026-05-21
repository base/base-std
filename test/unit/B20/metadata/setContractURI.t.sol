// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

contract B20SetContractURITest is B20Test {
    /// @notice Verifies setContractURI reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only admin may update the URI; checks AccessControlUnauthorizedAccount
    function test_setContractURI_revert_unauthorized(address caller, string calldata newURI) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE)
        );
        token.setContractURI(newURI);
    }

    /// @notice Verifies setContractURI updates contractURI() to the new value
    /// @dev Read-after-write; canonical contractURI readback test lives in contractURI.t.sol.
    ///      Paired slot assertion: the `contractURI` field slot holds
    ///      the Solidity-encoded string value byte-for-byte.
    function test_setContractURI_success_updatesURI(string calldata newURI) public {
        vm.prank(admin);
        token.setContractURI(newURI);
        assertEq(token.contractURI(), newURI, "contractURI() must return the new value");
        assertEq(
            vm.load(address(token), MockB20Storage.contractURISlot()),
            _expectedStringFieldSlot(newURI),
            "contractURI field slot must hold the canonical string encoding"
        );
    }

    /// @notice Verifies setContractURI emits ContractURIUpdated()
    /// @dev ERC-7572 convention: the event is argument-free; integrators refetch via contractURI()
    function test_setContractURI_success_emitsContractURIUpdated(string calldata newURI) public {
        vm.expectEmit(false, false, false, false, address(token));
        emit IB20.ContractURIUpdated();
        vm.prank(admin);
        token.setContractURI(newURI);
    }
}
