// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

import {IB20} from "src/interfaces/IB20.sol";
import {IB20Security} from "src/interfaces/IB20Security.sol";

/// @notice Base test contract for `IB20Security` unit tests.
///
/// Extends `B20Test` because `IB20Security is IB20`: the inherited
/// surface (actors, labels, setUp wiring, the `_singleFeature` helper,
/// the `_grantRole` / `_mint` / `_pause` action wrappers) applies
/// unchanged to a security-variant token. The only security-specific
/// concerns at the base level are which variant the deployed token is
/// (controlled by `_deployToken`), and the variant-specific role
/// holders (`operator`, `burnFromActor`) plus a handful of helpers for
/// the announcement, share-ratio, redemption, and identifier surfaces.
///
/// The inherited `token` member is typed `IB20`. Tests that need the
/// variant-only surface (`announce`, `redeem`, etc.) cast inline via
/// the `security` view-helper.
contract B20SecurityTest is B20Test {
    // -- Security-variant role-holder actors --
    address internal operator = makeAddr("operator");
    address internal burnFromActor = makeAddr("burnFromActor");

    // ============================================================
    //              SECURITY-VARIANT IDENTIFIER FIXTURES
    // ============================================================
    // Test-only identifier-type keys (`CUSIP`, `FIGI`). The canonical
    // `ISIN` key lives on `TokenFactoryTest` as `IDENTIFIER_ISIN`
    // because the factory writes it during bootstrap too; CUSIP and
    // FIGI are post-creation additions exercised only by the variant
    // tests, so they belong on this base.

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
        vm.label(burnFromActor, "burnFromActor");
    }

    /// @inheritdoc B20Test
    /// @dev Override deploys a security-variant token via the factory mock.
    ///      The factory etches `MockB20Security` runtime bytecode at the
    ///      computed address, seeds `identifiers["ISIN"]` and
    ///      `minimumRedeemable` directly via vm.store, grants the initial
    ///      admin, then closes the bootstrap window.
    function _deployToken() internal virtual override returns (IB20) {
        return IB20(_createSecurity());
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

    /// @notice Grants `BURN_FROM_ROLE` to the `burnFromActor` actor as
    ///         the admin, idempotent.
    function _grantBurnFrom() internal {
        bytes32 role = security().BURN_FROM_ROLE();
        if (!token.hasRole(role, burnFromActor)) _grantRole(role, burnFromActor);
    }

    // ============================================================
    //                       SHARE-RATIO HELPERS
    // ============================================================

    /// @notice Sets the share ratio via the `operator` actor, lazily
    ///         granting `SECURITY_OPERATOR_ROLE` on first call.
    function _updateShareRatio(uint256 newRatio) internal {
        _grantOperator();
        vm.prank(operator);
        security().updateShareRatio(newRatio);
    }

    // ============================================================
    //                        REDEMPTION HELPERS
    // ============================================================

    /// @notice Sets the minimum-redeemable floor via the admin actor.
    function _updateMinimumRedeemable(uint256 newMinimum) internal {
        vm.prank(admin);
        security().updateMinimumRedeemable(newMinimum);
    }

    /// @notice Sets the REDEEM_SENDER_POLICY slot via the admin actor.
    ///         Use `ALWAYS_ALLOW_ID` (0) or `ALWAYS_BLOCK_ID` (1) for
    ///         the policy registry's built-in sentinels.
    /// @dev Resolves the policy-type bytes32 BEFORE `vm.prank` so the
    ///      prank applies to `updatePolicy`, not to the view call that
    ///      resolves the constant.
    function _setRedeemPolicy(uint64 policyId) internal {
        bytes32 policyName = security().REDEEM_SENDER_POLICY();
        vm.prank(admin);
        token.updatePolicy(policyName, policyId);
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
    //                  POLICY-TYPE INDEXER OVERRIDE
    // ============================================================

    /// @notice Variant-specific policy-type indexer that extends
    ///         `B20Test._knownPolicyType`'s 4-element codomain with
    ///         `REDEEM_SENDER_POLICY`. Tests that fuzz over the
    ///         security variant's full supported set use this; tests
    ///         that fuzz over base-only types use the inherited 4-set.
    function _knownSecurityPolicyType(uint8 idx) internal view returns (bytes32) {
        uint8 i = idx % 5;
        if (i < 4) return _knownPolicyType(i);
        return security().REDEEM_SENDER_POLICY();
    }

    /// @notice Extends `_isKnownPolicyType` with the variant's own
    ///         redeem-side type.
    function _isKnownSecurityPolicyType(bytes32 policyName) internal view returns (bool) {
        return _isKnownPolicyType(policyName) || policyName == security().REDEEM_SENDER_POLICY();
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
    bytes32 internal constant BURN_FROM_ROLE = keccak256("BURN_FROM_ROLE");
    bytes32 internal constant REDEEM_SENDER_POLICY = keccak256("REDEEM_SENDER_POLICY");
}
