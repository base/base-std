// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20TransferFromWithMemoTest is B20Test {
    /// @notice Verifies transferFromWithMemo inherits all transferFrom guards
    /// @dev Reuse-of-guards invariant; concrete guard tests live in transferFrom.t.sol
    function test_transferFromWithMemo_revert_inheritsTransferFromGuards(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        // unimplemented
    }

    /// @notice Verifies transferFromWithMemo performs the same balance and allowance updates as transferFrom
    /// @dev Accounting and spend-tracking unchanged from transferFrom
    function test_transferFromWithMemo_success_movesBalanceAndDecreasesAllowance(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        // unimplemented
    }

    /// @notice Verifies transferFromWithMemo emits Transfer then Memo, in that order
    /// @dev Memo is the second log; canonical Memo test for the transferFrom path
    function test_transferFromWithMemo_success_emitsTransferThenMemo(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        // unimplemented
    }

    /// @notice Verifies transferFromWithMemo returns true on success
    /// @dev Matches transferFrom's return-value contract
    function test_transferFromWithMemo_success_returnsTrue(
        address caller,
        address from,
        address to,
        uint256 amount,
        bytes32 memo
    ) public {
        // unimplemented
    }
}
