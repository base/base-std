// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20, B20Constants} from "base-std-test/lib/mocks/MockB20.sol";

contract B20TotalSupplyTest is B20Test {
    /// @notice Verifies totalSupply returns the cumulative minted-minus-burned amount
    /// @dev Accounting invariant: totalSupply == sum of all balances == sum(mint) - sum(burn)
    function test_totalSupply_success_tracksMintAndBurn(address to, uint256 mintAmount, uint256 burnAmount) public {
        _assumeValidActor(to);
        mintAmount = _boundBalanceAmount(mintAmount);
        // Bound burnAmount to <= mintAmount so we don't underflow.
        burnAmount = bound(burnAmount, 0, mintAmount);

        _mint(to, mintAmount);
        assertEq(token.totalSupply(), mintAmount, "totalSupply after mint");

        // Grant BURN_ROLE to the recipient so they can burn from their own balance.
        _grantRole(B20Constants.BURN_ROLE, to);
        vm.prank(to);
        token.burn(burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount, "totalSupply after burn");
    }

    /// @notice Verifies totalSupply is zero on a freshly-created token with no initial supply
    /// @dev Default-state read for a token created without bootstrap mints in initCalls
    function test_totalSupply_success_zeroOnFreshToken() public view {
        // B20Test.setUp deploys a token with no initCalls, so no initial mints.
        assertEq(token.totalSupply(), 0, "fresh token must have zero supply");
    }
}
