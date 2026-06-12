// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
///         compile against the current interface. Each test tags the change it guards with a
///         trailing `Regression: BOP-XXX.` line.
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
    ///      Regression: BOP-248.
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
    ///      selector must not resolve. Regression: BOP-249.
    function test_multiplier_success_renamedFromShareRatio(uint256 rawBalance) public {
        rawBalance = bound(rawBalance, 0, type(uint128).max);

        // New surface resolves and behaves (1:1 at the WAD default).
        assertEq(asset().multiplier(), asset().WAD_PRECISION(), "fresh multiplier must default to WAD");
        assertEq(asset().toScaledBalance(rawBalance), rawBalance, "toScaledBalance is identity at WAD");
        assertEq(asset().toRawBalance(rawBalance), rawBalance, "toRawBalance is identity at WAD");

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
    //               METADATA vs OPERATOR GATING
    // ============================================================
    // The asset variant splits authority: the metadata setters (updateName / updateSymbol /
    // updateContractURI / updateExtraMetadata) are gated by METADATA_ROLE, while the operator
    // actions (announce / updateMultiplier) are gated by OPERATOR_ROLE. The tests below pin that
    // split from both sides.

    /// @notice Verifies `updateExtraMetadata` is gated by METADATA_ROLE, not OPERATOR_ROLE
    /// @dev An OPERATOR_ROLE-only holder is rejected with the METADATA_ROLE selector; a
    ///      METADATA_ROLE holder succeeds. Regression: BOP-248.
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

    /// @notice Verifies `updateMultiplier` is gated by OPERATOR_ROLE, not METADATA_ROLE
    /// @dev A METADATA_ROLE-only holder is rejected with the OPERATOR_ROLE selector — the inverse
    ///      of the metadata-gating test, confirming the two authorities are distinct. Regression: BOP-248.
    function test_updateMultiplier_revert_metadataRoleInsufficient(uint256 newMultiplier) public {
        newMultiplier = bound(newMultiplier, 1, type(uint128).max);
        _grantRole(B20Constants.METADATA_ROLE, bob);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IB20.AccessControlUnauthorizedAccount.selector, bob, B20Constants.OPERATOR_ROLE)
        );
        asset().updateMultiplier(newMultiplier);
    }

    /// @notice Verifies METADATA_ROLE is administered by DEFAULT_ADMIN_ROLE on a freshly created token
    /// @dev The asset variant does not set a custom admin for METADATA_ROLE, so it defaults to
    ///      DEFAULT_ADMIN_ROLE (the default admin grants/revokes METADATA_ROLE). Authority over
    ///      metadata *operations* is separate and split per the two tests above. Regression: BOP-248.
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
    ///      drift desyncs the gate. Regression: BOP-257.
    function test_b20Asset_success_keyedOnAssetNamespace() public pure {
        assertEq(
            ActivationRegistryFeatureList.B20_ASSET,
            keccak256("base.b20_asset"),
            "B20_ASSET must equal keccak256(\"base.b20_asset\")"
        );
    }

    /// @notice Verifies the asset feature is not keyed on either retired namespace
    /// @dev Asserting the asset id differs from both retired preimages locks against an accidental
    ///      revert to the old `base.b20_security` / `base.b20_token` namespace string. Regression: BOP-257.
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
