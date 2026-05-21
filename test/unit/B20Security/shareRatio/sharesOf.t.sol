// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20SecurityTest} from "test/lib/B20SecurityTest.sol";

contract B20SecuritySharesOfTest is B20SecurityTest {
    /// @notice Verifies sharesOf is zero for an account with no balance
    /// @dev Property: empty balance => zero shares regardless of the ratio.
    function test_sharesOf_success_zeroForEmptyAccount(address account, uint256 ratio) public {
        _assumeValidActor(account);
        ratio = bound(ratio, 1, type(uint256).max);
        _updateShareRatio(ratio);
        assertEq(security().sharesOf(account), 0, "empty account must have zero shares");
    }

    /// @notice Verifies sharesOf returns the balance unchanged on the default WAD ratio
    /// @dev Default 1:1 mapping; sharesOf collapses to balanceOf when the ratio is WAD.
    function test_sharesOf_success_identityOnWadDefault(address account, uint256 amount) public {
        _assumeValidActor(account);
        amount = bound(amount, 0, type(uint128).max);
        if (amount > 0) _mint(account, amount);
        assertEq(security().sharesOf(account), token.balanceOf(account), "default ratio: sharesOf == balanceOf");
        assertEq(security().sharesOf(account), amount, "default ratio: sharesOf == minted amount");
    }

    /// @notice Verifies sharesOf scales the held balance by the active ratio
    /// @dev Property: sharesOf(a) == balanceOf(a) * ratio / WAD. Fuzz balance and ratio over
    ///      the overflow-safe range.
    function test_sharesOf_success_scalesByStoredRatio(address account, uint256 amount, uint256 ratio) public {
        _assumeValidActor(account);
        amount = bound(amount, 1, type(uint128).max);
        ratio = bound(ratio, 1, type(uint128).max);
        _mint(account, amount);
        _updateShareRatio(ratio);
        assertEq(
            security().sharesOf(account),
            (amount * ratio) / security().WAD_PRECISION(),
            "sharesOf must apply balance * ratio / WAD"
        );
    }
}
