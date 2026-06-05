// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20UpdateSymbolTest is B20Test {
    /// @notice Verifies updateSymbol reverts when caller lacks METADATA_ROLE
    /// @dev Access control: only METADATA_ROLE holders may rename (separated from
    ///      DEFAULT_ADMIN_ROLE per IB20 spec). Checks AccessControlUnauthorizedAccount.
    function test_updateSymbol_revert_unauthorized(address caller, string calldata newSymbol) public {
        _assumeValidCaller(caller);
        vm.assume(!token.hasRole(B20Constants.METADATA_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.METADATA_ROLE)
        );
        token.updateSymbol(newSymbol);
    }

    /// @notice Verifies updateSymbol updates symbol() to the new value
    /// @dev Read-after-write; canonical symbol readback test lives in symbol.t.sol.
    ///      Paired slot assertion: the `symbol` field slot holds the
    ///      Solidity-encoded string value byte-for-byte.
    function test_updateSymbol_success_updatesSymbol(string calldata newSymbol) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.prank(admin);
        token.updateSymbol(newSymbol);
        assertEq(token.symbol(), newSymbol, "symbol() must return the new value");
        assertEq(
            vm.load(address(token), MockB20Storage.symbolSlot()),
            _expectedStringFieldSlot(newSymbol),
            "symbol field slot must hold the canonical string encoding"
        );
    }

    /// @notice Verifies updateSymbol emits SymbolUpdated(updater, newSymbol)
    /// @dev Event integrity; canonical SymbolUpdated emission test
    function test_updateSymbol_success_emitsSymbolUpdated(string calldata newSymbol) public {
        _grantRole(B20Constants.METADATA_ROLE, admin);
        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.SymbolUpdated(admin, newSymbol);
        vm.prank(admin);
        token.updateSymbol(newSymbol);
    }

    /// @notice Verifies updateSymbol does NOT emit EIP712DomainChanged and does NOT change DOMAIN_SEPARATOR
    /// @dev Symbol is intentionally NOT part of the EIP-712 domain (only `name` is). This is the
    ///      paired negative for updateName's domain-invalidation test: a symbol rename must not
    ///      perturb outstanding permit signatures or trigger an off-chain domain re-fetch.
    function test_updateSymbol_success_doesNotAffectEIP712Domain(string calldata newSymbol) public {
        bytes32 before = token.DOMAIN_SEPARATOR();
        _grantRole(B20Constants.METADATA_ROLE, admin);

        vm.recordLogs();
        vm.prank(admin);
        token.updateSymbol(newSymbol);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(
                logs[i].topics[0] != IB20.EIP712DomainChanged.selector, "updateSymbol must not emit EIP712DomainChanged"
            );
        }
        assertEq(token.DOMAIN_SEPARATOR(), before, "DOMAIN_SEPARATOR must not change on symbol update");
    }
}
