// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

contract B20UpdateNameTest is B20Test {
    /// @notice Verifies updateName reverts when caller lacks METADATA_ROLE
    /// @dev Access control: only METADATA_ROLE holders may rename (separated from
    ///      DEFAULT_ADMIN_ROLE per IB20 spec so metadata authority can be delegated
    ///      to a corporate-actions desk). Checks AccessControlUnauthorizedAccount.
    function test_updateName_revert_unauthorized(address caller, string calldata newName) public {
        _assumeValidCaller(caller);
        // Admin doesn't hold METADATA_ROLE by default either; only filter out callers we've
        // explicitly granted the role.
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        token.updateName(newName);
    }

    /// @notice Verifies updateName updates name() to the new value
    /// @dev Read-after-write; canonical name readback test lives in name.t.sol.
    ///      Paired slot assertion: the `name` field slot holds the
    ///      Solidity-encoded short/long string value byte-for-byte. For
    ///      long strings this checks only the field slot (which holds
    ///      `length * 2 + 1`); the body chunks at `keccak256(slot)+i`
    ///      are exercised by the FullLayout spec.
    function test_updateName_success_updatesName(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateName(newName);
        assertEq(token.name(), newName, "name() must return the new value");
        assertEq(
            vm.load(address(token), MockB20Storage.nameSlot()),
            _expectedStringFieldSlot(newName),
            "name field slot must hold the canonical string encoding"
        );
    }

    /// @notice Verifies updateName emits NameUpdated(updater, newName)
    /// @dev Event integrity; canonical NameUpdated emission test
    function test_updateName_success_emitsNameUpdated(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.NameUpdated(admin, newName);
        vm.prank(admin);
        token.updateName(newName);
    }
}
