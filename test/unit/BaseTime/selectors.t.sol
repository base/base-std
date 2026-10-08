// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {IBaseTime} from "base-std/interfaces/IBaseTime.sol";

/// @notice Pins each `IBaseTime` selector to the value exposed by the BaseTime predeploy.
contract BaseTimeSelectorsTest is Test {
    /// @notice `timestampMillisPart()` selector equals `0x7b2fea99`.
    function test_timestampMillisPart_selector_pinned() public pure {
        assertEq(IBaseTime.timestampMillisPart.selector, bytes4(0x7b2fea99), "timestampMillisPart selector");
    }

    /// @notice `timestampMs()` selector equals `0x5745a677`.
    function test_timestampMs_selector_pinned() public pure {
        assertEq(IBaseTime.timestampMs.selector, bytes4(0x5745a677), "timestampMs selector");
    }

    /// @notice `version()` selector equals `0x54fd4d50`.
    function test_version_selector_pinned() public pure {
        assertEq(IBaseTime.version.selector, bytes4(0x54fd4d50), "version selector");
    }
}
