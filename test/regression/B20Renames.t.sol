// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";

import {B20AssetTest} from "base-std-test/lib/B20AssetTest.sol";
import {ActivationRegistryFeatureList} from "base-std-test/lib/mocks/ActivationRegistryFeatureList.sol";

/// @title  B20 rename regression suite
///
/// @notice Locks in the *renames* from the B-20 asset rework: the operator role
///         surface (`OPERATOR_ROLE`), share-ratio scaling
///         (`sharesToTokensRatio`/`toShares`/`sharesOf`/`updateShareRatio` → `multiplier`/
///         `toScaledBalance`/`scaledBalanceOf`/`updateMultiplier`), the METADATA/OPERATOR
///         authority split, and the `base.b20_asset` activation namespace. Each test asserts the
///         new surface is present and correct AND the old surface is gone, so the rename cannot
///         silently regress in either the Solidity reference or the `base/base` Rust precompile
///         (under live precompile mode).
///
/// @dev    Old-selector absence is checked with low-level calls (the token carries no fallback, so
///         a retired selector cannot resolve); new surface is checked with typed calls that only
///         compile against the current interface.
contract B20RenamesTest is B20AssetTest {
    /// @dev Asserts a removed selector no longer resolves on the token surface.
    function _assertSelectorRemoved(bytes memory callData, string memory err) internal {
        (bool ok,) = address(token).call(callData);
        assertFalse(ok, err);
    }

    // ============================================================
    //                      OPERATOR ROLE
    // ============================================================

    /// @notice Verifies the operator role is exposed as `OPERATOR_ROLE`.
    /// @dev The wire value (`keccak256("OPERATOR_ROLE")`) and library source-of-truth must agree.
    function test_operatorRole_success_renamedFromSecurityOperator() public view {
        assertEq(asset().OPERATOR_ROLE(), keccak256("OPERATOR_ROLE"), "OPERATOR_ROLE must equal its keccak preimage");
        assertEq(asset().OPERATOR_ROLE(), B20Constants.OPERATOR_ROLE, "OPERATOR_ROLE must match B20Constants");
    }

    // ============================================================
    //                        MULTIPLIER
    // ============================================================

    /// @notice Verifies share-ratio scaling is exposed under the `multiplier` names and the legacy
    ///         share-ratio selectors are gone
    /// @dev The new getters resolve (a fresh token reports a WAD multiplier) and every legacy
    ///      selector must not resolve.
    function test_multiplier_success_renamedFromShareRatio(uint256 rawBalance) public {
        rawBalance = bound(rawBalance, 0, type(uint128).max);

        // New surface resolves and behaves (1:1 at the WAD default).
        assertEq(asset().multiplier(), asset().WAD_PRECISION(), "fresh multiplier must default to WAD");
        assertEq(asset().toUIAmount(rawBalance), rawBalance, "toUIAmount is identity at WAD");
        assertEq(asset().fromUIAmount(rawBalance), rawBalance, "fromUIAmount is identity at WAD");

        // Legacy share-ratio surface is gone.
        _assertSelectorRemoved(
            abi.encodeWithSignature("sharesToTokensRatio()"),
            "sharesToTokensRatio() must not resolve (renamed to multiplier())"
        );
        _assertSelectorRemoved(
            abi.encodeWithSignature("toShares(uint256)", rawBalance),
            "toShares(uint256) must not resolve (renamed to toScaledBalance)"
        );
        _assertSelectorRemoved(
            abi.encodeWithSignature("sharesOf(address)", alice),
            "sharesOf(address) must not resolve (renamed to scaledBalanceOf)"
        );
        _assertSelectorRemoved(
            abi.encodeWithSignature("updateShareRatio(uint256)", rawBalance),
            "updateShareRatio(uint256) must not resolve (renamed to updateMultiplier)"
        );
    }

    // ============================================================
    //             MULTIPLIER EVENT + ERC-8056 SURFACE
    // ============================================================

    bytes32 internal constant UI_MULTIPLIER_UPDATED_SIG = keccak256("UIMultiplierUpdated(uint256,uint256,uint256)");
    bytes32 internal constant LEGACY_MULTIPLIER_UPDATED_SIG = keccak256("MultiplierUpdated(uint256)");

    /// @notice Verifies the canonical scheduled setter is `updateUIMultiplier(uint256,uint256)`, that
    ///         the pre-rename `setUIMultiplier(uint256,uint256)` selector is gone, and that the
    ///         scheduled setter emits only the ERC-8056 `UIMultiplierUpdated` (the deprecated
    ///         `MultiplierUpdated` is reserved for the instant `updateMultiplier`).
    /// @dev `updateUIMultiplier` is the rename of `setUIMultiplier`; the old selector must not resolve.
    function test_scheduledSetter_success_renamedFromSetUIMultiplier(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _grantOperator();
        vm.recordLogs();
        vm.prank(operator);
        asset().updateUIMultiplier(newMultiplier, block.timestamp + 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(
            _firstLogIndex(logs, UI_MULTIPLIER_UPDATED_SIG), -1, "UIMultiplierUpdated(old,new,effAt) must be emitted"
        );
        assertEq(
            _firstLogIndex(logs, LEGACY_MULTIPLIER_UPDATED_SIG),
            -1,
            "scheduled updateUIMultiplier must NOT emit the deprecated MultiplierUpdated"
        );
        // The pre-rename scheduled selector is gone.
        _assertSelectorRemoved(
            abi.encodeWithSignature("setUIMultiplier(uint256,uint256)", newMultiplier, block.timestamp + 1),
            "setUIMultiplier(uint256,uint256) must not resolve (renamed to updateUIMultiplier)"
        );
    }

    /// @notice Verifies the ERC-8056 surface resolves and aliases the native B20 names
    /// @dev `uiMultiplier` aliases `multiplier`; `balanceOfUI` aliases `scaledBalanceOf`; the pending
    ///      surface, `totalSupplyUI`, `toUIAmount`/`fromUIAmount`, and `supportsInterface` all
    ///      resolve. These typed calls only compile against the current interface, so their presence
    ///      is the guard.
    function test_erc8056Surface_success_aliasesResolve(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        if (amount > 0) _mint(alice, amount);
        assertEq(asset().uiMultiplier(), asset().multiplier(), "uiMultiplier must alias multiplier");
        assertEq(asset().balanceOfUI(alice), asset().scaledBalanceOf(alice), "balanceOfUI must alias scaledBalanceOf");
        assertEq(asset().newUIMultiplier(), asset().uiMultiplier(), "no-pending: newUIMultiplier == uiMultiplier");
        assertEq(asset().effectiveAt(), 0, "no-pending: effectiveAt == 0");
        assertEq(asset().totalSupplyUI(), token.totalSupply(), "default multiplier: totalSupplyUI == totalSupply");
        assertEq(asset().toUIAmount(amount), amount, "toUIAmount identity at WAD default");
        assertEq(asset().fromUIAmount(amount), amount, "fromUIAmount identity at WAD default");
        assertTrue(asset().supportsInterface(0xa60bf13d), "IScaledUIAmount (0xa60bf13d) must be advertised");
        assertTrue(asset().supportsInterface(0x57854fc3), "IScaledUIAmountConversion (0x57854fc3) must be advertised");
    }

    /// @notice Verifies the deprecated `toScaledBalance` / `toRawBalance` are retained in `IB20Asset`
    ///         (declared deprecated) and behave identically to the ERC-8056 `toUIAmount` / `fromUIAmount`.
    /// @dev Deprecation-not-removal: the legacy conversion selectors stay advertised (marked
    ///      deprecated) and dialable so block explorers and existing integrations keep working.
    function test_conversion_deprecated_stillDialable(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        _updateMultiplier(2 * asset().WAD_PRECISION());

        assertEq(asset().toScaledBalance(amount), asset().toUIAmount(amount), "toScaledBalance must equal toUIAmount");
        assertEq(asset().toRawBalance(amount), asset().fromUIAmount(amount), "toRawBalance must equal fromUIAmount");
    }

    // ============================================================
    //               METADATA vs OPERATOR GATING
    // ============================================================
    // The asset variant splits authority: the metadata setters (updateName / updateSymbol /
    // updateContractURI / updateExtraMetadata) are gated by METADATA_ROLE, while the operator
    // actions (announce / updateUIMultiplier) are gated by OPERATOR_ROLE. The tests below pin that
    // split from both sides.

    /// @notice Verifies `updateExtraMetadata` is gated by METADATA_ROLE, not OPERATOR_ROLE
    /// @dev An OPERATOR_ROLE-only holder is rejected with the METADATA_ROLE selector; a
    ///      METADATA_ROLE holder succeeds.
    function test_updateExtraMetadata_success_gatedByMetadataRole(string calldata value) public {
        // Operator (OPERATOR_ROLE only) cannot write metadata.
        _grantOperator();
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, operator, B20Constants.METADATA_ROLE)
        );
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);

        // METADATA_ROLE holder can.
        _grantRole(B20Constants.METADATA_ROLE, bob);
        vm.prank(bob);
        asset().updateExtraMetadata(METADATA_EXAMPLE_1, value);
        assertEq(asset().extraMetadata(METADATA_EXAMPLE_1), value, "metadata write by METADATA_ROLE must persist");
    }

    /// @notice Verifies `updateUIMultiplier` is gated by OPERATOR_ROLE, not METADATA_ROLE
    /// @dev A METADATA_ROLE-only holder is rejected with the OPERATOR_ROLE selector — the inverse
    ///      of the metadata-gating test, confirming the two authorities are distinct.
    function test_updateUIMultiplier_revert_metadataRoleInsufficient(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _grantRole(B20Constants.METADATA_ROLE, bob);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, bob, B20Constants.OPERATOR_ROLE)
        );
        asset().updateUIMultiplier(newMultiplier, block.timestamp + 1);
    }

    /// @notice Verifies the deprecated `updateMultiplier` is retained in `IB20Asset` (declared
    ///         deprecated) and behaves identically to `updateUIMultiplier`.
    /// @dev Deprecation-not-removal: the legacy selector stays advertised (marked deprecated) and
    ///      dialable so block explorers and existing integrations keep working; it emits both the
    ///      deprecated `MultiplierUpdated` and the ERC-8056 `UIMultiplierUpdated`.
    function test_updateMultiplier_deprecated_stillDialable(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _grantOperator();
        vm.recordLogs();
        vm.prank(operator);
        asset().updateMultiplier(newMultiplier);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(
            _firstLogIndex(logs, UI_MULTIPLIER_UPDATED_SIG),
            -1,
            "deprecated updateMultiplier must emit the ERC-8056 UIMultiplierUpdated"
        );
        assertGt(
            _firstLogIndex(logs, LEGACY_MULTIPLIER_UPDATED_SIG),
            -1,
            "deprecated updateMultiplier must also emit MultiplierUpdated"
        );
        assertEq(asset().multiplier(), newMultiplier, "deprecated updateMultiplier must set the current multiplier");
    }

    /// @notice Verifies METADATA_ROLE is administered by DEFAULT_ADMIN_ROLE on a freshly created token
    /// @dev The asset variant does not set a custom admin for METADATA_ROLE, so it defaults to
    ///      DEFAULT_ADMIN_ROLE (the default admin grants/revokes METADATA_ROLE). Authority over
    ///      metadata *operations* is separate and split per the two tests above.
    function test_metadataRole_success_administeredByDefaultAdmin() public view {
        assertEq(
            token.getRoleAdmin(B20Constants.METADATA_ROLE),
            B20Constants.DEFAULT_ADMIN_ROLE,
            "METADATA_ROLE admin must default to DEFAULT_ADMIN_ROLE"
        );
    }

    // ============================================================
    //               ACTIVATION FEATURE NAMESPACE
    // ============================================================

    /// @notice Verifies the asset activation feature is keyed on the `base.b20_asset` namespace
    /// @dev This is the cross-language contract with the Rust `ActivationFeature` enum; a preimage
    ///      drift desyncs the gate.
    function test_b20Asset_success_keyedOnAssetNamespace() public pure {
        assertEq(
            ActivationRegistryFeatureList.B20_ASSET,
            keccak256("base.b20_asset"),
            "B20_ASSET must equal keccak256(\"base.b20_asset\")"
        );
    }

    /// @notice Verifies the asset feature is not keyed on either retired namespace
    /// @dev Asserting the asset id differs from both retired preimages locks against an accidental
    ///      revert to the old `base.b20_security` / `base.b20_token` namespace string.
    function test_b20Asset_success_notKeyedOnLegacyNamespaces() public pure {
        assertTrue(
            ActivationRegistryFeatureList.B20_ASSET != keccak256("base.b20_security"),
            "B20_ASSET must not use the retired base.b20_security namespace"
        );
        assertTrue(
            ActivationRegistryFeatureList.B20_ASSET != keccak256("base.b20_token"),
            "B20_ASSET must not use the retired base.b20_token namespace"
        );
    }
}
