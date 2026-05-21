// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "src/interfaces/IB20.sol";

import {B20Test} from "test/lib/B20Test.sol";
import {MockB20, B20Constants} from "test/lib/mocks/MockB20.sol";
import {MockB20Storage} from "test/lib/mocks/MockB20Storage.sol";

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
        mintedAmount = bound(mintedAmount, 2, type(uint128).max);
        newCap = bound(newCap, 0, mintedAmount - 1);

        _mint(alice, mintedAmount);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IB20.InvalidSupplyCap.selector, mintedAmount, newCap));
        token.updateSupplyCap(newCap);
    }

    /// @notice Verifies updateSupplyCap raises the cap to a value above the current totalSupply
    /// @dev Read-after-write: supplyCap returns newCap. Fresh token has totalSupply == 0,
    ///      so any cap is valid. Paired slot assertion verifies
    ///      `supplyCap` slot reflects the write.
    function test_updateSupplyCap_success_raisesCap(uint256 newCap) public {
        vm.prank(admin);
        token.updateSupplyCap(newCap);
        assertEq(token.supplyCap(), newCap, "supplyCap must equal newCap");
        assertEq(
            uint256(vm.load(address(token), MockB20Storage.supplyCapSlot())),
            newCap,
            "supplyCap slot must reflect the raise"
        );
    }

    /// @notice Verifies updateSupplyCap lowers the cap to a value at or above the current totalSupply
    /// @dev Cap may be lowered as long as totalSupply <= newCap.
    ///      Paired slot assertion verifies `supplyCap` slot reflects the lower.
    function test_updateSupplyCap_success_lowersCap(uint256 newCap) public {
        // Mint some supply, then bound newCap >= mintedAmount.
        uint256 mintedAmount = 1000;
        newCap = bound(newCap, mintedAmount, type(uint256).max);

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
        uint256 oldCap = token.supplyCap();

        vm.expectEmit(true, false, false, true, address(token));
        emit IB20.SupplyCapUpdated(admin, oldCap, newCap);
        vm.prank(admin);
        token.updateSupplyCap(newCap);
    }
}
