// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";

import {B20FactoryLibTest} from "base-std-test/lib/B20FactoryLibTest.sol";

contract B20FactoryLibConcatTest is B20FactoryLibTest {
    /// @notice Concatenating two empty arrays produces an empty result.
    /// @dev    Boundary case for the length-zero allocation path.
    function test_concat_success_bothEmptyProducesEmpty() public pure {
        bytes[] memory result = B20FactoryLib.concat(new bytes[](0), new bytes[](0));
        assertEq(result.length, 0, "empty + empty must produce empty");
    }

    /// @notice An empty `head` with a populated `tail` returns `tail` verbatim.
    /// @dev    Common case for "no typed-core grants, just caller extras";
    ///         must not duplicate, drop, or reorder entries.
    function test_concat_success_emptyHeadReturnsTail(uint8 lenSeed) public pure {
        uint256 len = bound(uint256(lenSeed), 1, 8);
        bytes[] memory tail = new bytes[](len);
        for (uint256 i = 0; i < len; i++) {
            tail[i] = abi.encodePacked("tail-", uint8(i));
        }

        bytes[] memory result = B20FactoryLib.concat(new bytes[](0), tail);

        assertEq(result.length, len, "length must equal tail length");
        for (uint256 i = 0; i < len; i++) {
            assertEq(result[i], tail[i], "tail entry must appear at the same index");
        }
    }

    /// @notice A populated `head` with an empty `tail` returns `head` verbatim.
    /// @dev    Mirror of the previous test; covers the
    ///         "no caller extras" case.
    function test_concat_success_emptyTailReturnsHead(uint8 lenSeed) public pure {
        uint256 len = bound(uint256(lenSeed), 1, 8);
        bytes[] memory head = new bytes[](len);
        for (uint256 i = 0; i < len; i++) {
            head[i] = abi.encodePacked("head-", uint8(i));
        }

        bytes[] memory result = B20FactoryLib.concat(head, new bytes[](0));

        assertEq(result.length, len, "length must equal head length");
        for (uint256 i = 0; i < len; i++) {
            assertEq(result[i], head[i], "head entry must appear at the same index");
        }
    }

    /// @notice Both arrays populated: result is `head` followed by `tail`,
    ///         in order.
    /// @dev    Pins the contract `[head[0], ..., head[m-1], tail[0], ..., tail[n-1]]`
    ///         that the rest of the library leans on when stitching
    ///         typed-core bundles with caller extras.
    function test_concat_success_preservesHeadThenTailOrder(uint8 headLenSeed, uint8 tailLenSeed) public pure {
        uint256 headLen = bound(uint256(headLenSeed), 1, 8);
        uint256 tailLen = bound(uint256(tailLenSeed), 1, 8);
        bytes[] memory head = new bytes[](headLen);
        bytes[] memory tail = new bytes[](tailLen);
        for (uint256 i = 0; i < headLen; i++) {
            head[i] = abi.encodePacked("head-", uint8(i));
        }
        for (uint256 i = 0; i < tailLen; i++) {
            tail[i] = abi.encodePacked("tail-", uint8(i));
        }

        bytes[] memory result = B20FactoryLib.concat(head, tail);

        assertEq(result.length, headLen + tailLen, "result length must be sum of inputs");
        for (uint256 i = 0; i < headLen; i++) {
            assertEq(result[i], head[i], "head entry must appear at index i");
        }
        for (uint256 j = 0; j < tailLen; j++) {
            assertEq(result[headLen + j], tail[j], "tail entry must appear after head");
        }
    }
}
