// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

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

    /// @notice Verifies updateName emits the ERC-5267 EIP712DomainChanged signal
    /// @dev Domain-change notification: `name` participates in the EIP-712 domain,
    ///      so a successful rename invalidates outstanding permit signatures and
    ///      cached domain separators. The parameterless event is the ERC-5267
    ///      handshake for re-introspection.
    function test_updateName_success_emitsEIP712DomainChanged(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.expectEmit(false, false, false, false, address(token));
        emit IB20.EIP712DomainChanged();
        vm.prank(admin);
        token.updateName(newName);
    }

    /// @notice Verifies updateName emits NameUpdated then EIP712DomainChanged in that exact order
    /// @dev Event ordering is part of the interface contract per IB20: indexers join the two
    ///      events into a single rebrand record and rely on the ordering to disambiguate from
    ///      any other domain-affecting mutation that might be introduced later.
    function test_updateName_success_emitsEventsInOrder(string calldata newName) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.recordLogs();
        vm.prank(admin);
        token.updateName(newName);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "updateName must emit exactly two events");
        assertEq(logs[0].topics[0], IB20.NameUpdated.selector, "first event must be NameUpdated");
        assertEq(logs[1].topics[0], IB20.EIP712DomainChanged.selector, "second event must be EIP712DomainChanged");
    }

    /// @notice Verifies updateName invalidates the DOMAIN_SEPARATOR
    /// @dev End-to-end check that the EIP712DomainChanged signal is not just a noise event:
    ///      the domain separator actually moves to a new value, which is what makes the
    ///      previously-signed permit digests un-recoverable to their original signers.
    function test_updateName_success_invalidatesDomainSeparator(string calldata newName) public {
        vm.assume(keccak256(bytes(newName)) != keccak256(bytes(token.name())));

        bytes32 before = token.DOMAIN_SEPARATOR();
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateName(newName);

        assertTrue(token.DOMAIN_SEPARATOR() != before, "DOMAIN_SEPARATOR must change after rename");
    }
}
