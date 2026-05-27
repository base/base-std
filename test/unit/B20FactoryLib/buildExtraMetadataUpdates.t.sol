// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "src/lib/B20FactoryLib.sol";
import {IB20Asset} from "src/interfaces/IB20Asset.sol";

import {B20FactoryLibTest} from "test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibBuildExtraMetadataUpdatesTest is B20FactoryLibTest {
    /// @notice External wrapper that re-exposes
    ///         `buildExtraMetadataUpdates` for revert-path tests.
    ///         Internal library calls inline into the test contract;
    ///         `vm.expectRevert` requires the revert one CALL frame
    ///         deeper, so revert tests must dispatch through an external
    ///         entry point via `this.callBuildExtraMetadataUpdates`.
    function callBuildExtraMetadataUpdates(string[] memory types, string[] memory values)
        external
        pure
        returns (bytes[] memory)
    {
        return B20FactoryLib.buildExtraMetadataUpdates(types, values);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the helper reverts when `identifierTypes` and
    ///         `identifierValues` differ in length.
    /// @dev    Mirrors the length-check semantics of
    ///         `buildRoleGrants(bytes32[], address[])`.
    function test_buildExtraMetadataUpdates_revert_lengthMismatch(uint8 typesLenSeed, uint8 valuesLenSeed) public {
        uint256 typesLen = bound(uint256(typesLenSeed), 0, 16);
        uint256 valuesLen = bound(uint256(valuesLenSeed), 0, 16);
        vm.assume(typesLen != valuesLen);
        string[] memory types = new string[](typesLen);
        string[] memory values = new string[](valuesLen);

        vm.expectRevert(abi.encodeWithSelector(B20FactoryLib.LengthMismatch.selector, typesLen, valuesLen));
        this.callBuildExtraMetadataUpdates(types, values);
    }

    /*//////////////////////////////////////////////////////////////
                                SUCCESS
    //////////////////////////////////////////////////////////////*/

    /// @notice Empty input arrays produce an empty result.
    /// @dev    Boundary case; unlike `buildRoleGrants` there is no
    ///         skip-on-empty rule, so length tracks input exactly.
    function test_buildExtraMetadataUpdates_success_emptyInputProducesEmpty() public pure {
        bytes[] memory result = B20FactoryLib.buildExtraMetadataUpdates(new string[](0), new string[](0));
        assertEq(result.length, 0, "empty inputs must produce an empty result");
    }

    /// @notice Every input pair produces one
    ///         `updateExtraMetadata(type, value)` init call, in
    ///         input order, with no entries elided.
    /// @dev    Pins ordering and the no-skip semantics; even empty
    ///         strings are passed through (the token, not this helper,
    ///         validates).
    function test_buildExtraMetadataUpdates_success_emitsAllPairsInOrder(uint8 lenSeed) public pure {
        uint256 len = bound(uint256(lenSeed), 1, 8);
        string[] memory types = new string[](len);
        string[] memory values = new string[](len);
        for (uint256 i = 0; i < len; i++) {
            types[i] = string(abi.encodePacked("TYPE", _toAscii(i)));
            values[i] = string(abi.encodePacked("VAL", _toAscii(i)));
        }

        bytes[] memory result = B20FactoryLib.buildExtraMetadataUpdates(types, values);

        assertEq(result.length, len, "every pair must produce one init call");
        for (uint256 i = 0; i < len; i++) {
            assertEq(
                result[i],
                abi.encodeCall(IB20Asset.updateExtraMetadata, (types[i], values[i])),
                "ordering must follow input"
            );
        }
    }

    /// @notice Pairs containing empty strings are passed through verbatim.
    /// @dev    The helper does NOT skip empty entries — validation lives
    ///         on the token. This pins that behavior against a future
    ///         "skip empty pairs" mis-edit.
    function test_buildExtraMetadataUpdates_success_emptyStringsArePassedThrough() public pure {
        string[] memory types = new string[](3);
        string[] memory values = new string[](3);
        types[0] = "ISIN";
        values[0] = "";
        types[1] = "";
        values[1] = "us-cusip";
        types[2] = "FIGI";
        values[2] = "BBG000B9XRY4";

        bytes[] memory result = B20FactoryLib.buildExtraMetadataUpdates(types, values);

        assertEq(result.length, 3, "no entry may be elided");
        assertEq(
            result[0],
            abi.encodeCall(IB20Asset.updateExtraMetadata, (types[0], values[0])),
            "empty value passed through"
        );
        assertEq(
            result[1],
            abi.encodeCall(IB20Asset.updateExtraMetadata, (types[1], values[1])),
            "empty type passed through"
        );
        assertEq(
            result[2],
            abi.encodeCall(IB20Asset.updateExtraMetadata, (types[2], values[2])),
            "fully populated pair preserved"
        );
    }

    /// @dev Render a small integer as a 1-byte ASCII digit for fixture
    ///      strings. Bounded by callers (`len <= 8`) so always single-digit.
    function _toAscii(uint256 i) private pure returns (bytes1) {
        return bytes1(uint8(0x30) + uint8(i));
    }
}
