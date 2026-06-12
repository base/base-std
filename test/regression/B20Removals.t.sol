// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";

/// @title  B20 removal regression suite
///
/// @notice Locks in the *removals* from the B-20 asset rework (the redemption subsystem,
///         batched burn / burn-from, and the `DEFAULT` token variant). Each test asserts that a
///         function/selector that USED to exist on the surface no longer resolves, so a future
///         reintroduction — or a Rust precompile in `base/base` that still exposes the retired
///         surface — fails here.
///
/// @dev    These are *selector-absence* assertions: the token mock (and the live precompile in
///         live precompile mode) carries no fallback, so a call to a removed selector cannot succeed. The
///         same test body is meaningful against the mock (proves the Solidity reference dropped
///         the surface) and against the live precompile under `LIVE_PRECOMPILES=true ... --fork-url`
///         (proves `base/base` dropped it too). Args are irrelevant — dispatch fails before decoding
///         for an unknown selector — but old signatures are reproduced verbatim so each `bytes4`
///         matches the historical selector exactly.
///
///         Each test tags the change it guards with a trailing `Regression: BOP-XXX.` line.
contract B20RemovalsTest is B20AssetTest {
    /// @dev Asserts a low-level call of `signature` (with `args` appended) to the token reverts,
    ///      i.e. the selector no longer resolves on the B-20 surface.
    function _assertSelectorRemoved(bytes memory callData, string memory err) internal {
        (bool ok,) = address(token).call(callData);
        assertFalse(ok, err);
    }

    // ============================================================
    //                    REDEMPTION SUBSYSTEM
    // ============================================================

    /// @notice Verifies the `redeem(uint256)` selector no longer resolves on the B-20 surface
    /// @dev A reintroduced `redeem` entrypoint trips this. Regression: BOP-251.
    function test_redeem_revert_selectorRemoved(uint256 amount) public {
        _assertSelectorRemoved(abi.encodeWithSignature("redeem(uint256)", amount), "redeem(uint256) must not resolve");
    }

    /// @notice Verifies the `redeemWithMemo(uint256,bytes32)` selector no longer resolves
    /// @dev Memo'd variant of the removed redeem path. Regression: BOP-251.
    function test_redeemWithMemo_revert_selectorRemoved(uint256 amount, bytes32 memo) public {
        _assertSelectorRemoved(
            abi.encodeWithSignature("redeemWithMemo(uint256,bytes32)", amount, memo),
            "redeemWithMemo(uint256,bytes32) must not resolve"
        );
    }

    /// @notice Verifies the `minimumRedeemable()` getter no longer resolves
    /// @dev The redemption floor getter was removed with the redemption subsystem. Regression: BOP-251.
    function test_minimumRedeemable_revert_selectorRemoved() public {
        _assertSelectorRemoved(abi.encodeWithSignature("minimumRedeemable()"), "minimumRedeemable() must not resolve");
    }

    /// @notice Verifies the `updateMinimumRedeemable(uint256)` setter no longer resolves
    /// @dev The redemption floor setter was removed with the redemption subsystem. Regression: BOP-251.
    function test_updateMinimumRedeemable_revert_selectorRemoved(uint256 newMin) public {
        _assertSelectorRemoved(
            abi.encodeWithSignature("updateMinimumRedeemable(uint256)", newMin),
            "updateMinimumRedeemable(uint256) must not resolve"
        );
    }

    /// @notice Verifies the `REDEEM_SENDER_POLICY()` policy-scope constant no longer resolves
    /// @dev The redemption policy lane was removed with the redemption subsystem. Regression: BOP-251.
    function test_redeemSenderPolicy_revert_selectorRemoved() public {
        _assertSelectorRemoved(
            abi.encodeWithSignature("REDEEM_SENDER_POLICY()"), "REDEEM_SENDER_POLICY() must not resolve"
        );
    }

    /// @notice Verifies the `PausableFeature` enum has no fourth (`REDEEM`) member
    /// @dev `isPaused(PausableFeature)` ABI-decodes its arg as the enum; an out-of-range value (3)
    ///      reverts (Panic 0x21). Index 2 (`BURN`) still decodes, bracketing the enum at exactly
    ///      {TRANSFER, MINT, BURN}. Regression: BOP-251.
    function test_isPaused_revert_noRedeemFeature() public {
        _assertSelectorRemoved(
            abi.encodeWithSignature("isPaused(uint8)", uint8(3)),
            "isPaused must reject enum index 3 (out of PausableFeature range)"
        );

        (bool ok,) = address(token).call(abi.encodeWithSignature("isPaused(uint8)", uint8(2)));
        assertTrue(ok, "isPaused must still accept enum index 2 (BURN)");
    }

    /// @notice Verifies the all-features-paused bitmask covers exactly three features
    /// @dev `ALL_FEATURES_PAUSED == 7` is `TRANSFER | MINT | BURN` (0b111); a fourth feature would
    ///      push it to 15. Pins the feature count at the library source-of-truth. Regression: BOP-251.
    function test_allFeaturesPaused_success_threeFeatureBitmask() public pure {
        assertEq(B20Constants.ALL_FEATURES_PAUSED, 7, "ALL_FEATURES_PAUSED must be TRANSFER|MINT|BURN (0b111)");
    }

    // ============================================================
    //                 BATCHED BURN / BURN-FROM
    // ============================================================

    /// @notice Verifies the `batchBurn(address[],uint256[])` selector no longer resolves
    /// @dev Only `batchMint` remains on the asset variant. Regression: BOP-250.
    function test_batchBurn_revert_selectorRemoved(address account, uint256 amount) public {
        address[] memory accounts = _singletonAddresses(account);
        uint256[] memory amounts = _singletonUints(amount);
        _assertSelectorRemoved(
            abi.encodeWithSignature("batchBurn(address[],uint256[])", accounts, amounts),
            "batchBurn(address[],uint256[]) must not resolve"
        );
    }

    /// @notice Verifies the `BURN_FROM_ROLE()` role constant no longer resolves
    /// @dev `burnBlocked` (gated by `BURN_BLOCKED_ROLE`) is the remaining seize path. Regression: BOP-250.
    function test_burnFromRole_revert_selectorRemoved() public {
        _assertSelectorRemoved(abi.encodeWithSignature("BURN_FROM_ROLE()"), "BURN_FROM_ROLE() must not resolve");
    }

    // ============================================================
    //                      DEFAULT VARIANT
    // ============================================================

    /// @notice Verifies the factory rejects a third (`DEFAULT`) variant discriminator
    /// @dev `B20Variant` is now exactly {ASSET=0, STABLECOIN=1}. `createB20` ABI-decodes `variant`
    ///      as the enum, so discriminator 2 reverts (Panic 0x21) before reaching the factory body;
    ///      a reintroduced third variant would let this succeed. Regression: BOP-253.
    function test_createB20_revert_defaultVariantRemoved(bytes32 salt) public {
        bytes memory params = abi.encode(_assetParams());
        (bool ok,) = address(factory)
            .call(abi.encodeWithSelector(IB20Factory.createB20.selector, uint8(2), salt, params, new bytes[](0)));
        assertFalse(ok, "createB20 must reject variant discriminator 2 (out of B20Variant range)");
    }
}
