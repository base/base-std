// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

contract B20AssetScaledBalanceOfTest is B20AssetTest {
    /// @notice Verifies scaledBalanceOf is zero for an account with no balance
    /// @dev Property: empty balance => zero scaled balance regardless of the multiplier.
    function test_scaledBalanceOf_success_zeroForEmptyAccount(address account, uint256 newMultiplier) public {
        _assumeValidActor(account);
        newMultiplier = bound(newMultiplier, 1, type(uint256).max);
        _updateMultiplier(newMultiplier);
        assertEq(asset().scaledBalanceOf(account), 0, "empty account must have zero scaled balance");
    }

    /// @notice Verifies scaledBalanceOf returns the balance unchanged on the default WAD multiplier
    /// @dev Default 1:1 mapping; scaledBalanceOf collapses to balanceOf when the multiplier is WAD.
    function test_scaledBalanceOf_success_identityOnWadDefault(address account, uint256 amount) public {
        _assumeValidActor(account);
        amount = bound(amount, 0, type(uint128).max);
        if (amount > 0) _mint(account, amount);
        assertEq(
            asset().scaledBalanceOf(account),
            token.balanceOf(account),
            "default multiplier: scaledBalanceOf == balanceOf"
        );
        assertEq(asset().scaledBalanceOf(account), amount, "default multiplier: scaledBalanceOf == minted amount");
    }

    /// @notice Verifies scaledBalanceOf scales the held balance by the active multiplier
    /// @dev Property: scaledBalanceOf(a) == balanceOf(a) * multiplier / WAD. Fuzz balance and
    ///      multiplier over the overflow-safe range.
    function test_scaledBalanceOf_success_scalesByStoredMultiplier(
        address account,
        uint256 amount,
        uint256 newMultiplier
    ) public {
        _assumeValidActor(account);
        amount = bound(amount, 1, type(uint128).max);
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _mint(account, amount);
        _updateMultiplier(newMultiplier);
        assertEq(
            asset().scaledBalanceOf(account),
            (amount * newMultiplier) / asset().WAD_PRECISION(),
            "scaledBalanceOf must apply balance * multiplier / WAD"
        );
    }

    /// @notice Verifies scaledBalanceOf applies the WAD fallback when the stored multiplier is zero
    /// @dev A stored `multiplier` of zero resolves as `WAD_PRECISION` on the read surface.
    ///      `updateMultiplier(0)` now reverts (InvalidMultiplier), so we zero the slot via
    ///      vm.store to isolate the read-path fallback from write-path validation.
    function test_scaledBalanceOf_success_explicitZeroMultiplierFallsBackToWad(address account, uint256 amount) public {
        _assumeValidActor(account);
        amount = bound(amount, 0, type(uint128).max);
        if (amount > 0) _mint(account, amount);
        _updateMultiplier(5e18); // seed a non-zero value first
        vm.store(address(token), MockB20AssetStorage.multiplierSlot(), bytes32(0)); // zero the slot directly
        assertEq(
            asset().scaledBalanceOf(account), amount, "stored zero multiplier must produce identity (WAD fallback)"
        );
    }
}
