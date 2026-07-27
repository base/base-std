// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

import {IERC165} from "base-std/interfaces/IERC165.sol";
import {
    IScaledUIAmount,
    IScaledUIAmountNewUIMultiplier,
    IScaledUIAmountBalances
} from "base-std/interfaces/IScaledUIAmount.sol";

contract B20AssetSupportsInterfaceTest is B20AssetTest {
    // Published ERC-8056 / ERC-165 interface identifiers.
    bytes4 internal constant ERC165_ID = 0x01ffc9a7;
    bytes4 internal constant SCALED_UI_AMOUNT_ID = 0xa60bf13d;
    bytes4 internal constant NEW_UI_MULTIPLIER_ID = 0x4bd27648;
    bytes4 internal constant BALANCES_ID = 0xd890fd71;

    /// @notice Verifies the four claimed interface IDs are advertised
    /// @dev ERC-165 itself plus the ERC-8056 core, pending, and Balances extensions.
    function test_supportsInterface_success_claimedIds() public view {
        assertTrue(asset().supportsInterface(ERC165_ID), "must advertise IERC165");
        assertTrue(asset().supportsInterface(SCALED_UI_AMOUNT_ID), "must advertise IScaledUIAmount");
        assertTrue(asset().supportsInterface(NEW_UI_MULTIPLIER_ID), "must advertise IScaledUIAmountNewUIMultiplier");
        assertTrue(asset().supportsInterface(BALANCES_ID), "must advertise IScaledUIAmountBalances");
    }

    /// @notice Verifies an unknown interface ID returns false
    function test_supportsInterface_success_unknownFalse(bytes4 interfaceId) public view {
        vm.assume(interfaceId != ERC165_ID);
        vm.assume(interfaceId != SCALED_UI_AMOUNT_ID);
        vm.assume(interfaceId != NEW_UI_MULTIPLIER_ID);
        vm.assume(interfaceId != BALANCES_ID);
        assertFalse(asset().supportsInterface(interfaceId), "unknown interface must not be advertised");
    }

    /// @notice Verifies each computed `type(I).interfaceId` equals its published ERC-8056 hex
    /// @dev Guards against selector drift in the interface definitions
    function test_supportsInterface_success_interfaceIdsMatchPublishedHex() public pure {
        assertEq(type(IERC165).interfaceId, ERC165_ID, "IERC165 id");
        assertEq(type(IScaledUIAmount).interfaceId, SCALED_UI_AMOUNT_ID, "IScaledUIAmount id");
        assertEq(
            type(IScaledUIAmountNewUIMultiplier).interfaceId, NEW_UI_MULTIPLIER_ID, "IScaledUIAmountNewUIMultiplier id"
        );
        assertEq(type(IScaledUIAmountBalances).interfaceId, BALANCES_ID, "IScaledUIAmountBalances id");
    }
}
