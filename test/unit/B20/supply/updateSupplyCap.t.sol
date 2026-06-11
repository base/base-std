// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20UpdateSupplyCapTest is B20Test {
    /// @notice Verifies updateSupplyCap reverts when caller lacks DEFAULT_ADMIN_ROLE
    /// @dev Access control: only admin may resize the cap; checks AccessControlUnauthorizedAccount
    function test_updateSupplyCap_revert_unauthorized(address caller, uint256 newCap) public {
        _assumeValidCaller(caller);
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20.AccessControlUnauthorizedAccount.selector, caller, B20Constants.DEFAULT_ADMIN_ROLE
            )
        );
        token.updateSupplyCap(newCap);
    }

    /// @notice Verifies updateSupplyCap reverts when newCap is below the current totalSupply
    /// @dev Invariant: never invalidate already-issued supply; checks InvalidSupplyCap(currentSupply, proposedCap)
    function test_updateSupplyCap_revert_belowCurrentSupply(uint256 mintedAmount, uint256 newCap) public {
        mintedAmount = bound(mintedAmount, 2, B20Constants.MAX_SUPPLY_CAP);
        newCap = bound(newCap, 0, mintedAmount - 1);

        _mint(alice, mintedAmount);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSupplyCap.selector, mintedAmount, newCap));
        token.updateSupplyCap(newCap);
    }

    /// @notice Verifies updateSupplyCap reverts when newCap exceeds the uint128.max ceiling
    /// @dev Upper bound: the cap (and therefore totalSupply) can never exceed B20Constants.MAX_SUPPLY_CAP.
    ///      Reuses InvalidSupplyCap(currentSupply, proposedCap); a fresh token has currentSupply == 0.
    function test_updateSupplyCap_revert_aboveMaximum(uint256 newCap) public {
        newCap = bound(newCap, B20Constants.MAX_SUPPLY_CAP + 1, type(uint256).max);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSupplyCap.selector, 0, newCap));
        token.updateSupplyCap(newCap);
    }

    /// @notice Verifies updateSupplyCap raises the cap to a value above the current totalSupply
    /// @dev Read-after-write: supplyCap returns newCap. Fresh token has totalSupply == 0,
    ///      so any cap within the uint128.max ceiling is valid. Paired slot assertion verifies
    ///      `supplyCap` slot reflects the write.
    function test_updateSupplyCap_success_raisesCap(uint256 newCap) public {
        newCap = bound(newCap, 0, B20Constants.MAX_SUPPLY_CAP);
        vm.prank(admin);
        token.updateSupplyCap(newCap);
        assertEq(token.supplyCap(), newCap, "supplyCap must equal newCap");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.supplyCapSlot())),
            newCap,
            "supplyCap slot must reflect the raise"
        );
    }

    /// @notice Verifies updateSupplyCap accepts the maximum permitted cap (B20Constants.MAX_SUPPLY_CAP)
    /// @dev Boundary: the uint128.max ceiling is inclusive — setting the cap to exactly the
    ///      maximum is the unbounded ("no cap") configuration and must succeed.
    function test_updateSupplyCap_success_atMaximum() public {
        vm.prank(admin);
        token.updateSupplyCap(B20Constants.MAX_SUPPLY_CAP);
        assertEq(token.supplyCap(), B20Constants.MAX_SUPPLY_CAP, "supplyCap must equal the maximum");
    }

    /// @notice Verifies updateSupplyCap lowers the cap to a value at or above the current totalSupply
    /// @dev Cap may be lowered as long as totalSupply <= newCap.
    ///      Paired slot assertion verifies `supplyCap` slot reflects the lower.
    function test_updateSupplyCap_success_lowersCap(uint256 newCap) public {
        // Mint some supply, then bound newCap into [mintedAmount, uint128.max].
        uint256 mintedAmount = 1000;
        newCap = bound(newCap, mintedAmount, B20Constants.MAX_SUPPLY_CAP);

        _mint(alice, mintedAmount);

        vm.prank(admin);
        token.updateSupplyCap(newCap);
        assertEq(token.supplyCap(), newCap, "supplyCap must equal newCap");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.supplyCapSlot())),
            newCap,
            "supplyCap slot must reflect the lower"
        );
    }

    /// @notice Verifies updateSupplyCap emits SupplyCapUpdated(updater, oldCap, newCap)
    /// @dev Event integrity; canonical SupplyCapUpdated emission test
    function test_updateSupplyCap_success_emitsSupplyCapUpdated(uint256 newCap) public {
        newCap = bound(newCap, 0, B20Constants.MAX_SUPPLY_CAP);
        uint256 oldCap = token.supplyCap();

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.SupplyCapUpdated(admin, oldCap, newCap);
        vm.prank(admin);
        token.updateSupplyCap(newCap);
    }
}
