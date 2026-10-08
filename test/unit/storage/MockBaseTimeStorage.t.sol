// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeTest} from "base-std-test/lib/BaseTimeTest.sol";
import {MockBaseTimeStorage} from "base-std-test/lib/mocks/MockBaseTimeStorage.sol";

/// @notice Pins `MockBaseTime`'s storage to the real predeploy's layout: `uint16 timestampMillisPart`
///         in the low-order 2 bytes of slot 0.
contract MockBaseTimeStorageTest is BaseTimeTest {
    /// @notice Verifies `TIMESTAMP_MILLIS_PART_SLOT` is slot 0.
    function test_TIMESTAMP_MILLIS_PART_SLOT_success_isSlotZero() public pure {
        assertEq(MockBaseTimeStorage.TIMESTAMP_MILLIS_PART_SLOT, bytes32(0), "timestampMillisPart must live in slot 0");
    }

    /// @notice Verifies a value written to slot 0 is what `timestampMillisPart` reads.
    function test_timestampMillisPart_success_readsSlotZero(uint16 part) public {
        _setTimestampMillisPart(part);
        assertEq(
            vm.load(address(baseTime), MockBaseTimeStorage.TIMESTAMP_MILLIS_PART_SLOT),
            bytes32(uint256(part)),
            "slot 0 must hold the written value"
        );
        assertEq(baseTime.timestampMillisPart(), part, "timestampMillisPart must read slot 0");
    }

    /// @notice Verifies `timestampMillisPart` reads only the low-order 2 bytes of slot 0.
    /// @dev    Fills the high 30 bytes with `high`; a uint16 at offset 0 must ignore them.
    function test_timestampMillisPart_success_readsLowOrderBytes(uint16 part, uint240 high) public {
        vm.assume(high != 0);
        vm.store(
            address(baseTime),
            MockBaseTimeStorage.TIMESTAMP_MILLIS_PART_SLOT,
            bytes32((uint256(high) << 16) | uint256(part))
        );
        assertEq(baseTime.timestampMillisPart(), part, "timestampMillisPart must read the low-order 2 bytes");
    }
}
