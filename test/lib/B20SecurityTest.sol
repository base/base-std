// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

import {IB20Security} from "src/interfaces/IB20Security.sol";

/// @notice Base test contract for `IB20Security` unit tests.
///
/// Extends `B20Test` for the inherited test surface (actors, labels,
/// setUp wiring, the `_singleFeature` helper, the `_grantRole` /
/// `_mint` / `_pause` action wrappers, and the security-variant token
/// deployed by `_deployToken`). Adds the variant-specific role holder
/// (`operator`) plus helpers for the announcement, multiplier,
/// and identifier surfaces.
///
/// The inherited `token` member is typed `IB20`. Tests that need the
/// variant-only surface (`announce`, `batchMint`, etc.) cast inline via
/// the `security` view-helper.
contract B20SecurityTest is B20Test {
    // -- Security-variant role-holder actors --
    address internal operator = makeAddr("operator");

    // ============================================================
    //              SECURITY-VARIANT IDENTIFIER FIXTURES
    // ============================================================
    // Test-only identifier-type keys (`ISIN`, `CUSIP`, `FIGI`). All
    // three are post-creation additions exercised only by the variant
    // tests; the factory no longer seeds any identifier at bootstrap.

    /// @notice Identifier-type key for the ISIN entry (International
    ///         Securities Identification Number). Test-fixture only.
    string internal constant IDENTIFIER_ISIN = "ISIN";

    /// @notice Identifier-type key for the CUSIP entry (US/Canada
    ///         securities identifier). Test-fixture only.
    string internal constant IDENTIFIER_CUSIP = "CUSIP";

    /// @notice Identifier-type key for the FIGI entry (Bloomberg's
    ///         financial-instrument global identifier). Test-fixture only.
    string internal constant IDENTIFIER_FIGI = "FIGI";

    // -- Setup --
    function setUp() public virtual override {
        super.setUp();
        vm.label(operator, "operator");
    }

    // ============================================================
    //                   VARIANT CAST CONVENIENCE
    // ============================================================

    /// @notice Returns `token` cast to `IB20Security`. Saves typing
    ///         `IB20Security(address(token))` at every callsite.
    function security() internal view returns (IB20Security) {
        return IB20Security(address(token));
    }

    // ============================================================
    //                    SECURITY-ROLE HELPERS
    // ============================================================

    /// @notice Grants `SECURITY_OPERATOR_ROLE` to the `operator` actor as
    ///         the admin, idempotent.
    function _grantOperator() internal {
        bytes32 role = security().SECURITY_OPERATOR_ROLE();
        if (!token.hasRole(role, operator)) _grantRole(role, operator);
    }

    // ============================================================
    //                       MULTIPLIER HELPERS
    // ============================================================

    /// @notice Sets the multiplier via the `operator` actor, lazily
    ///         granting `SECURITY_OPERATOR_ROLE` on first call.
    function _updateMultiplier(uint256 newMultiplier) internal {
        _grantOperator();
        vm.prank(operator);
        security().updateMultiplier(newMultiplier);
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
        security().announce(internalCalls, id, description, uri);
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
    // values match `security().SECURITY_OPERATOR_ROLE()` etc. by
    // construction; the per-constant test in
    // `test/unit/B20Security/constants/` pins that down.

    bytes32 internal constant SECURITY_OPERATOR_ROLE = keccak256("SECURITY_OPERATOR_ROLE");
}
