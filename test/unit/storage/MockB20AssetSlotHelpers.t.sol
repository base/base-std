// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";
import {MockB20AssetStorage} from "base-std-test/lib/mocks/MockB20Storage.sol";

/// @notice Self-tests for `MockB20AssetStorage`'s pending-slot packed codecs.
///
/// @dev The pending multiplier lives in a single packed slot (offset 4 of the `base.b20.asset`
///      namespace: `uint128 multiplier | uint64 effectiveAt`). These verify the codecs' bit math
///      matches Solidity's struct packing — both as a pure round-trip and against a real slot
///      write — so a codec drifting from the canonical `PendingMultiplier` layout fails CI. The
///      Rust precompile impl uses the same helper outputs as its ground truth.
contract MockB20AssetSlotHelpersTest is B20AssetTest {
    /// @notice Verifies `packPendingMultiplier` is the inverse of the lane decoders.
    /// @dev Round-trip: pack a uint128 + uint64, decode, expect the inputs back.
    function test_packPendingMultiplier_success_roundtrips(uint128 multiplier, uint64 effectiveAt) public pure {
        uint256 packed = MockB20AssetStorage.packPendingMultiplier(multiplier, effectiveAt);
        assertEq(MockB20AssetStorage.pendingMultiplierValue(packed), multiplier, "multiplier lane");
        assertEq(MockB20AssetStorage.pendingEffectiveAt(packed), effectiveAt, "effectiveAt lane");
    }

    /// @notice Verifies the lane decoders read a real scheduled pending back out of slot 4.
    /// @dev Read-after-write: schedule via the public surface (which writes through the
    ///      `PendingMultiplier` struct), then `vm.load` slot 4 and decode both lanes.
    function test_pendingSlot_success_decodesScheduledPending(uint256 newMultiplier, uint256 effectiveAt) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        effectiveAt = bound(effectiveAt, block.timestamp + 1, type(uint64).max);

        _setUIMultiplier(newMultiplier, effectiveAt);

        uint256 packed = uint256(vm.load(address(token), MockB20AssetStorage.pendingSlot()));
        assertEq(
            uint256(MockB20AssetStorage.pendingMultiplierValue(packed)),
            newMultiplier,
            "pendingMultiplierValue must reflect the scheduled multiplier"
        );
        assertEq(
            uint256(MockB20AssetStorage.pendingEffectiveAt(packed)),
            effectiveAt,
            "pendingEffectiveAt must reflect the scheduled effectiveAt"
        );
    }
}
