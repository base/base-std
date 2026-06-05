// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20UpdateContractURITest is B20Test {
    /// @notice Verifies updateContractURI reverts when caller lacks METADATA_ROLE
    /// @dev Access control: only METADATA_ROLE holders may update the URI (separated
    ///      from DEFAULT_ADMIN_ROLE per IB20 spec so metadata authority can be
    ///      delegated to a corporate-actions desk). Checks AccessControlUnauthorizedAccount.
    function test_updateContractURI_revert_unauthorized(address caller, string calldata newURI) public {
        _assumeValidCaller(caller);
        // Admin doesn't hold METADATA_ROLE by default either; only filter out callers we've
        // explicitly granted the role.
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        token.updateContractURI(newURI);
    }

    /// @notice Verifies updateContractURI updates contractURI() to the new value
    /// @dev Read-after-write; canonical contractURI readback test lives in contractURI.t.sol.
    ///      Paired slot assertion: the `contractURI` field slot holds
    ///      the Solidity-encoded string value byte-for-byte.
    function test_updateContractURI_success_updatesURI(string calldata newURI) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateContractURI(newURI);
        assertEq(token.contractURI(), newURI, "contractURI() must return the new value");
        assertEq(
            vm.load(address(token), MockB20Storage.contractURISlot()),
            _expectedStringFieldSlot(newURI),
            "contractURI field slot must hold the canonical string encoding"
        );
    }

    /// @notice Verifies updateContractURI emits ContractURIUpdated()
    /// @dev ERC-7572 convention: the event is argument-free; integrators refetch via contractURI()
    function test_updateContractURI_success_emitsContractURIUpdated(string calldata newURI) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.expectEmit(false, false, false, false, address(token));
        emit IB20.ContractURIUpdated();
        vm.prank(admin);
        token.updateContractURI(newURI);
    }
}
