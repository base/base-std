// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IB20} from "base-std/interfaces/IB20.sol";

import {B20Test} from "base-std-test/lib/B20Test.sol";
import {MockB20} from "base-std-test/lib/mocks/MockB20.sol";

/// @title Differential check-order tests for `permit`.
///
/// @notice **Canonical order (Solidity reference):**
///         1. EXPIRED-SIGNATURE (`block.timestamp > deadline`) → `ExpiredSignature`
///         2. INVALID-SIGNER (`recovered == 0 || recovered != owner`) → `InvalidSigner`
///
///         C(2, 2) = 1 pair.
contract B20PermitRevertOrderTest is B20Test {
    /// @notice EXPIRED-SIGNATURE beats INVALID-SIGNER.
    /// @dev Passes a malformed signature (v=0 → ecrecover returns address(0))
    ///      with an already-expired deadline. The deadline check fires before
    ///      the signature is even decoded, so the expired error wins.
    function test_permit_revertOrder_expired_beats_invalidSigner(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline
    ) public {
        vm.assume(spender != address(0));
        deadline = bound(deadline, 0, block.timestamp - 1);
        // Malformed signature: v=0 is invalid (valid values are 27 or 28).
        uint8 v = 0;
        bytes32 r = bytes32(uint256(1));
        bytes32 s = bytes32(uint256(2));

        vm.expectRevert(abi.encodeWithSelector(IB20.ExpiredSignature.selector, deadline));
        token.permit(owner, spender, value, deadline, v, r, s);
    }
}
