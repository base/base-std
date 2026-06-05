// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";

import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

/// @notice Base test contract for `IB20Asset` unit tests.
///
/// Extends `B20Test` for the inherited test surface (actors, labels,
/// setUp wiring, the `_singleFeature` helper, the `_grantRole` /
/// `_mint` / `_pause` action wrappers, and the asset-variant token
/// deployed by `_deployToken`). Adds the variant-specific role holder
/// (`operator`) plus helpers for the announcement, multiplier,
/// and extra-metadata surfaces.
///
/// The inherited `token` member is typed `IB20`. Tests that need the
/// variant-only surface (`announce`, `batchMint`, etc.) cast inline via
/// the `asset` view-helper.
contract B20AssetTest is B20Test {
    // -- Asset-variant role-holder actors --
    address internal operator = makeAddr("operator");

    // ============================================================
    //           ASSET-VARIANT EXTRA-METADATA FIXTURES
    // ============================================================
    // Test-only metadata-entry keys. The `extraMetadata` surface is
    // a variant-agnostic key/value store; these three keys form a
    // coherent generic example so tests don't accidentally encode a
    // assets-specific assumption. All entries are post-creation
    // additions exercised only by the variant tests; the factory does
    // not seed any entry at bootstrap.

    /// @notice Example metadata-entry key #1. String value chosen for readability;
    ///         the constant name stays generic so tests don't encode any
    ///         variant-specific assumption about what keys mean.
    string internal constant METADATA_EXAMPLE_1 = "category";

    /// @notice Example metadata-entry key #2.
    string internal constant METADATA_EXAMPLE_2 = "region";

    /// @notice Example metadata-entry key #3.
    string internal constant METADATA_EXAMPLE_3 = "reference";

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();
        vm.label(operator, "operator");
    }

    // ============================================================
    //                   VARIANT CAST CONVENIENCE
    // ============================================================

    /// @notice Returns `token` cast to `IB20Asset`. Saves typing
    ///         `IB20Asset(address(token))` at every callsite.
    function asset() internal view returns (IB20Asset) {
        return IB20Asset(address(token));
    }

    // ============================================================
    //                    ASSET-ROLE HELPERS
    // ============================================================

    /// @notice Grants `OPERATOR_ROLE` to the `operator` actor as
    ///         the admin, idempotent.
    function _grantOperator() internal {
        bytes32 role = asset().OPERATOR_ROLE();
        if (!token.hasRole(role, operator)) _grantRole(role, operator);
    }

    // ============================================================
    //                       MULTIPLIER HELPERS
    // ============================================================

    /// @notice Sets the multiplier via the `operator` actor, lazily
    ///         granting `OPERATOR_ROLE` on first call.
    function _updateMultiplier(uint256 newMultiplier) internal {
        _grantOperator();
        vm.prank(operator);
        asset().updateMultiplier(newMultiplier);
    }

    // ============================================================
    //                      ANNOUNCEMENT HELPERS
    // ============================================================

    /// @notice Calls `announce` from the `operator` actor with explicit
    ///         caller, internalCalls, id, description, and URI.
    function _announce(
        address caller,
        bytes[] memory internalCalls,
        string memory id,
        string memory description,
        string memory uri
    ) internal {
        vm.prank(caller);
        asset().announce(internalCalls, id, description, uri);
    }

    /// @notice Calls `announce` with defaults: `operator` caller, empty
    ///         internalCalls, plain description and URI. The caller
    ///         supplies the id so successive `_announce()` invocations
    ///         within one test don't collide on the consumed-id guard.
    function _announce(string memory id) internal {
        _grantOperator();
        _announce(operator, new bytes[](0), id, "description", "https://disclosures.example/");
    }

    // ============================================================
    //                         BATCH HELPERS
    // ============================================================

    /// @notice Wraps a single address in a length-1 memory array.
    function _singletonAddresses(address account) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    /// @notice Wraps a single uint256 in a length-1 memory array.
    function _singletonUints(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    /// @notice Wraps a single bytes blob in a length-1 memory array.
    function _singletonBytes(bytes memory blob) internal pure returns (bytes[] memory blobs) {
        blobs = new bytes[](1);
        blobs[0] = blob;
    }

    // ============================================================
    //                      VARIANT-ONLY CONSTANTS
    // ============================================================
    // Compile-time copies of the contract's variant-only constants.
    // Tests reference these when they need the value in a context that
    // can't make a contract call (e.g. inside a struct literal). The
    // values match `asset().OPERATOR_ROLE()` etc. by construction;
    // the per-constant test in `test/unit/B20Asset/constants/` pins
    // that down.

    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
}
