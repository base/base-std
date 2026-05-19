// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20BurnWithMemoTest is B20Test {
    /// @notice Verifies burnWithMemo inherits all burn guards
    /// @dev Reuse-of-guards invariant; concrete guard tests live in burn.t.sol
    function test_burnWithMemo_revert_inheritsBurnGuards(uint256 amount, bytes32 memo) public {
        // unimplemented
    }

    /// @notice Verifies burnWithMemo debits caller and decreases totalSupply
    /// @dev Accounting unchanged from burn; the memo does not alter accounting
    function test_burnWithMemo_success_debitsAndDecreasesSupply(uint256 amount, bytes32 memo) public {
        // unimplemented
    }

    /// @notice Verifies burnWithMemo emits Transfer(caller, address(0), amount) then Memo(memo)
    /// @dev Event ordering: Memo follows Transfer; canonical Memo test for the burn path
    function test_burnWithMemo_success_emitsTransferThenMemo(uint256 amount, bytes32 memo) public {
        // unimplemented
    }
}
