// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";

import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

/// @notice Base test contract for `IB20Asset` unit tests.
///
/// Extends `B20Test` for the inherited surface (actors, labels, setUp
/// wiring, role helpers, and the asset-variant token deployed by
/// `_deployToken`). Adds asset-specific actors and helpers for the
/// multiplier surface.
///
/// The inherited `token` member is typed `IB20`. Tests that need
/// asset-only methods cast via the `asset()` helper.
contract B20AssetTest is B20Test {
    address internal operator = makeAddr("operator");

    string internal constant METADATA_EXAMPLE_1 = "category";
    string internal constant METADATA_EXAMPLE_2 = "region";
    string internal constant METADATA_EXAMPLE_3 = "reference";

    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    function setUp() public virtual override {
        super.setUp();
        vm.label(operator, "operator");
    }

    /// @notice Returns `token` cast to `IB20Asset`.
    function asset() internal view returns (IB20Asset) {
        return IB20Asset(address(token));
    }

    /// @notice Grants `OPERATOR_ROLE` to the `operator` actor as admin.
    function _grantOperator() internal {
        _grantRole(asset().OPERATOR_ROLE(), operator);
    }

    /// @notice Sets the multiplier via the `operator` actor.
    function _updateMultiplier(uint256 newMultiplier) internal {
        _grantOperator();
        vm.prank(operator);
        asset().updateMultiplier(newMultiplier);
    }

    /// @notice Posts an announcement from `caller` with the given fields.
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

    /// @notice Posts a pure-disclosure announcement from the `operator` actor.
    function _announce(string memory id) internal {
        _grantOperator();
        _announce(operator, new bytes[](0), id, "description", "https://disclosures.example/");
    }

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
}
