// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibBuildExtraMetadataUpdatesTest is B20FactoryLibTest {
    /// @notice External wrapper that re-exposes
    ///         `buildExtraMetadataUpdates` for revert-path tests.
    ///         Internal library calls inline into the test contract;
    ///         `vm.expectRevert` requires the revert one CALL frame
    ///         deeper, so revert tests must dispatch through an external
    ///         entry point via `this.callBuildExtraMetadataUpdates`.
    function callBuildExtraMetadataUpdates(string[] memory keys, string[] memory values)
        external
        pure
        returns (bytes[] memory)
    {
        return B20FactoryLib.buildExtraMetadataUpdates(keys, values);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the helper reverts when `keys` and `values` differ in length.
    /// @dev    Mirrors the length-check semantics of
    ///         `buildRoleGrants(bytes32[], address[])`.
    function test_buildExtraMetadataUpdates_revert_lengthMismatch(uint8 keysLenSeed, uint8 valuesLenSeed) public {
        uint256 keysLen = bound(uint256(keysLenSeed), 0, 16);
        uint256 valuesLen = bound(uint256(valuesLenSeed), 0, 16);
        vm.assume(keysLen != valuesLen);
        string[] memory keys = new string[](keysLen);
        string[] memory values = new string[](valuesLen);

        vm.expectRevert(abi.encodeWithSelector(B20FactoryLib.LengthMismatch.selector, keysLen, valuesLen));
        this.callBuildExtraMetadataUpdates(keys, values);
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
    ///         `updateExtraMetadata(key, value)` init call, in
    ///         input order, with no entries elided.
    /// @dev    Pins ordering and the no-skip semantics; even empty
    ///         strings are passed through (the token, not this helper,
    ///         validates).
    function test_buildExtraMetadataUpdates_success_emitsAllPairsInOrder(uint8 lenSeed) public pure {
        uint256 len = bound(uint256(lenSeed), 1, 8);
        string[] memory keys = new string[](len);
        string[] memory values = new string[](len);
        for (uint256 i = 0; i < len; i++) {
            keys[i] = string(abi.encodePacked("KEY", _toAscii(i)));
            values[i] = string(abi.encodePacked("VAL", _toAscii(i)));
        }

        bytes[] memory result = B20FactoryLib.buildExtraMetadataUpdates(keys, values);

        assertEq(result.length, len, "every pair must produce one init call");
        for (uint256 i = 0; i < len; i++) {
            assertEq(
                result[i],
                abi.encodeCall(IB20Asset.updateExtraMetadata, (keys[i], values[i])),
                "ordering must follow input"
            );
        }
    }

    /// @notice Pairs containing empty strings are passed through verbatim.
    /// @dev    The helper does NOT skip empty entries — validation lives
    ///         on the token. This pins that behavior against a future
    ///         "skip empty pairs" mis-edit.
    function test_buildExtraMetadataUpdates_success_emptyStringsArePassedThrough() public pure {
        string[] memory keys = new string[](3);
        string[] memory values = new string[](3);
        keys[0] = "category";
        values[0] = "";
        keys[1] = "";
        values[1] = "north-america";
        keys[2] = "reference";
        values[2] = "REF-2024-001";

        bytes[] memory result = B20FactoryLib.buildExtraMetadataUpdates(keys, values);

        assertEq(result.length, 3, "no entry may be elided");
        assertEq(
            result[0], abi.encodeCall(IB20Asset.updateExtraMetadata, (keys[0], values[0])), "empty value passed through"
        );
        assertEq(
            result[1], abi.encodeCall(IB20Asset.updateExtraMetadata, (keys[1], values[1])), "empty key passed through"
        );
        assertEq(
            result[2],
            abi.encodeCall(IB20Asset.updateExtraMetadata, (keys[2], values[2])),
            "fully populated pair preserved"
        );
    }

    /// @dev Render a small integer as a 1-byte ASCII digit for fixture
    ///      strings. Bounded by callers (`len <= 8`) so always single-digit.
    function _toAscii(uint256 i) private pure returns (bytes1) {
        return bytes1(uint8(0x30) + uint8(i));
    }
}
