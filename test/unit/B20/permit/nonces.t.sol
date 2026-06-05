// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {B20Test} from "base-std-test/lib/B20Test.sol";

contract B20NoncesTest is B20Test {
    /// @notice Verifies nonces returns zero for any account that has never permitted
    /// @dev Default state across the address space
    function test_nonces_success_zeroByDefault(address account) public view {
        assertEq(token.nonces(account), 0, "untouched account must have zero nonce");
    }

    /// @notice Verifies nonces advances by exactly one per successful permit
    /// @dev Replay protection: monotonic counter; canonical permit test lives in permit.t.sol
    function test_nonces_success_advancesPerPermit() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address spender = bob;
        uint256 value = 1000;
        uint256 deadline = type(uint256).max;

        uint256 nonceBefore = token.nonces(owner);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, spender, value, deadline);
        token.permit(owner, spender, value, deadline, v, r, s);
        assertEq(token.nonces(owner), nonceBefore + 1, "nonce must advance by 1");
    }
}
