// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "test/lib/B20Test.sol";

contract B20TotalSupplyTest is B20Test {
    /// @notice Verifies totalSupply returns the cumulative minted-minus-burned amount
    /// @dev Accounting invariant: totalSupply == sum of all balances == sum(mint) - sum(burn)
    function test_totalSupply_success_tracksMintAndBurn(address to, uint256 mintAmount, uint256 burnAmount) public {
        // unimplemented
    }

    /// @notice Verifies totalSupply is zero on a freshly-created token with no initial supply
    /// @dev Default-state read for a token created without bootstrap mints in initCalls
    function test_totalSupply_success_zeroOnFreshToken() public {
        // unimplemented
    }
}
