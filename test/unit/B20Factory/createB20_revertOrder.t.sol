// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";

import {B20FactoryTest} from "base-std-test/lib/B20FactoryTest.sol";

/// @title Differential check-order tests for `createB20`.
///
/// @notice `createB20` is a dispatcher: the variant byte selects an arm, then each
///         arm runs its own preconditions in sequence. This file pins the per-arm
///         ordering: VERSION beats each field-validation check inside an arm.
///         The cross-arm UNSUPPORTED-VARIANT-beats-arm-body ordering is pinned by
///         `test_createB20_revert_outOfRangeVariant` in `getTokenAddress.t.sol`
///         (raw-bytes ABI-decoder panic).
///
///         **Canonical order per variant arm (Solidity reference):**
///         - STABLECOIN: VERSION → INVALID-CURRENCY (format check on each byte)
///         - ASSET: VERSION (single guard; no body validation pairs to test)
contract B20FactoryCreateB20RevertOrderTest is B20FactoryTest {
    /// @notice For the STABLECOIN arm: VERSION beats INVALID-CURRENCY.
    /// @dev Both violations: unsupported version AND invalid currency byte. Version check
    ///      runs first inside the STABLECOIN arm body.
    function test_createB20_revertOrder_stablecoin_version_beats_invalidCurrency(
        address caller,
        uint8 badVersion,
        bytes32 salt
    ) public {
        _assumeValidCaller(caller);
        vm.assume(badVersion != 1);
        // Invalid currency (lowercase 'a' is not in A-Z) AND unsupported version.
        IB20Factory.B20StablecoinCreateParams memory p = _stablecoinParams("Test", "TST", admin, "abc");
        p.version = badVersion;

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IB20Factory.UnsupportedVersion.selector, badVersion, IB20Factory.B20Variant.STABLECOIN
            )
        );
        factory.createB20(IB20Factory.B20Variant.STABLECOIN, salt, abi.encode(p), new bytes[](0));
    }
}
